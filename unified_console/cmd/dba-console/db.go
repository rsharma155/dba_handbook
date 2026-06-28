package main

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	_ "github.com/microsoft/go-mssqldb"
)

const queryTimeout = 120 * time.Second

type connectConfig struct {
	Engine           string
	Host             string
	Port             int
	Database         string
	Username         string
	Password         string
	SSLMode          string
	TrustCertificate bool
}

type connectionHolder struct {
	ID       string
	Engine   string
	Database string
	DB       *sql.DB
	Config   connectConfig
}

func openConnection(cfg connectConfig) (*sql.DB, error) {
	cfg.Host = strings.TrimSpace(cfg.Host)
	if cfg.Host == "" {
		return nil, fmt.Errorf("host is required")
	}
	if cfg.Port == 0 {
		if cfg.Engine == "postgres" {
			cfg.Port = 5432
		} else {
			cfg.Port = 1433
		}
	}
	if cfg.Database == "" {
		if cfg.Engine == "postgres" {
			cfg.Database = "postgres"
		} else {
			cfg.Database = "master"
		}
	}

	var dsn string
	switch cfg.Engine {
	case "postgres":
		if cfg.SSLMode == "" {
			cfg.SSLMode = "prefer"
		}
		u := &url.URL{
			Scheme: "postgres",
			Host:   fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
			Path:   "/" + cfg.Database,
		}
		if cfg.Username != "" {
			u.User = url.UserPassword(cfg.Username, cfg.Password)
		}
		q := u.Query()
		q.Set("sslmode", cfg.SSLMode)
		u.RawQuery = q.Encode()
		dsn = u.String()
		db, err := sql.Open("pgx", dsn)
		if err != nil {
			return nil, err
		}
		db.SetConnMaxLifetime(30 * time.Minute)
		db.SetMaxOpenConns(4)
		if err := ping(db); err != nil {
			_ = db.Close()
			return nil, err
		}
		return db, nil

	case "mssql":
		u := &url.URL{
			Scheme: "sqlserver",
			Host:   fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
		}
		q := u.Query()
		q.Set("database", cfg.Database)
		q.Set("encrypt", "true")
		if cfg.TrustCertificate {
			q.Set("TrustServerCertificate", "true")
		} else {
			q.Set("TrustServerCertificate", "false")
		}
		if cfg.Username != "" {
			u.User = url.UserPassword(cfg.Username, cfg.Password)
		} else {
			q.Set("trusted_connection", "yes")
		}
		u.RawQuery = q.Encode()
		dsn = u.String()
		db, err := sql.Open("sqlserver", dsn)
		if err != nil {
			return nil, err
		}
		db.SetConnMaxLifetime(30 * time.Minute)
		db.SetMaxOpenConns(4)
		if err := ping(db); err != nil {
			_ = db.Close()
			return nil, err
		}
		return db, nil

	default:
		return nil, fmt.Errorf("unsupported engine: %s", cfg.Engine)
	}
}

func ping(db *sql.DB) error {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	return db.PingContext(ctx)
}

func describeConnection(db *sql.DB, engine, database string) (map[string]any, error) {
	info := map[string]any{
		"engine":  engine,
		"catalog": database,
		"label":   database,
	}
	ctx, cancel := context.WithTimeout(context.Background(), queryTimeout)
	defer cancel()

	var version string
	switch engine {
	case "postgres":
		err := db.QueryRowContext(ctx, "SELECT version()").Scan(&version)
		if err != nil {
			return info, err
		}
	default:
		err := db.QueryRowContext(ctx, "SELECT @@VERSION").Scan(&version)
		if err != nil {
			return info, err
		}
	}
	info["version"] = version
	return info, nil
}

func dbForExecute(holder *connectionHolder, database string) (*sql.DB, bool, error) {
	database = strings.TrimSpace(database)
	if database == "" || database == holder.Database {
		return holder.DB, false, nil
	}
	cfg := holder.Config
	cfg.Database = database
	db, err := openConnection(cfg)
	if err != nil {
		return nil, false, err
	}
	return db, true, nil
}

func splitSQLBatches(engine, sqlText string) []string {
	sqlText = strings.TrimSpace(sqlText)
	if sqlText == "" {
		return nil
	}
	switch engine {
	case "mssql":
		parts := regexpSplitGO(sqlText)
		var batches []string
		for _, p := range parts {
			p = strings.TrimSpace(p)
			if p != "" {
				batches = append(batches, p)
			}
		}
		return batches
	case "postgres":
		var lines []string
		for _, line := range strings.Split(sqlText, "\n") {
			if strings.HasPrefix(strings.TrimSpace(line), `\`) {
				continue
			}
			lines = append(lines, line)
		}
		cleaned := strings.TrimSpace(strings.Join(lines, "\n"))
		if cleaned == "" {
			return nil
		}
		return []string{cleaned}
	default:
		return []string{sqlText}
	}
}

func regexpSplitGO(sqlText string) []string {
	var batches []string
	var current strings.Builder
	for _, line := range strings.Split(sqlText, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.EqualFold(trimmed, "GO") || strings.HasPrefix(strings.ToUpper(trimmed), "GO ") {
			batches = append(batches, current.String())
			current.Reset()
			continue
		}
		current.WriteString(line)
		current.WriteByte('\n')
	}
	if current.Len() > 0 {
		batches = append(batches, current.String())
	}
	return batches
}

type columnMeta struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

type resultTable struct {
	Index    int              `json:"index"`
	Columns  []columnMeta     `json:"columns"`
	Rows     []map[string]any `json:"rows"`
	RowCount int              `json:"rowCount"`
}

func executeSQL(holder *connectionHolder, sqlText, database string) ([]resultTable, []map[string]any, error) {
	db, closeAfter, err := dbForExecute(holder, database)
	if err != nil {
		return nil, nil, err
	}
	if closeAfter {
		defer db.Close()
	}

	batches := splitSQLBatches(holder.Engine, sqlText)
	if len(batches) == 0 {
		return nil, nil, fmt.Errorf("no executable SQL after preprocessing")
	}

	ctx, cancel := context.WithTimeout(context.Background(), queryTimeout)
	defer cancel()

	var tables []resultTable
	var messages []map[string]any
	resultIndex := 0

	for _, batch := range batches {
		rows, err := db.QueryContext(ctx, batch)
		if err != nil {
			if isNoResultSetError(err) {
				res, execErr := db.ExecContext(ctx, batch)
				if execErr != nil {
					return tables, messages, execErr
				}
				if n, e := res.RowsAffected(); e == nil {
					resultIndex++
					messages = append(messages, map[string]any{
						"type":        "update",
						"updateCount": n,
						"index":       resultIndex,
					})
				}
				continue
			}
			return tables, messages, err
		}

		for {
			table, err := readResultSet(rows)
			if err != nil {
				rows.Close()
				return tables, messages, err
			}
			resultIndex++
			table.Index = resultIndex
			tables = append(tables, table)
			if !rows.NextResultSet() {
				rows.Close()
				break
			}
		}
	}

	return tables, messages, nil
}

func isNoResultSetError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "no result set") ||
		strings.Contains(msg, "does not return a result set")
}

func readResultSet(rows *sql.Rows) (resultTable, error) {
	cols, err := rows.Columns()
	if err != nil {
		return resultTable{}, err
	}
	types, err := rows.ColumnTypes()
	if err != nil {
		return resultTable{}, err
	}

	meta := make([]columnMeta, len(cols))
	for i, c := range cols {
		typeName := "string"
		if i < len(types) && types[i] != nil {
			typeName = types[i].DatabaseTypeName()
		}
		meta[i] = columnMeta{Name: c, Type: typeName}
	}

	var outRows []map[string]any
	for rows.Next() {
		values := make([]any, len(cols))
		ptrs := make([]any, len(cols))
		for i := range values {
			ptrs[i] = &values[i]
		}
		if err := rows.Scan(ptrs...); err != nil {
			return resultTable{}, err
		}
		row := make(map[string]any, len(cols))
		for i, col := range cols {
			row[col] = normalizeValue(values[i])
		}
		outRows = append(outRows, row)
	}
	if err := rows.Err(); err != nil {
		return resultTable{}, err
	}

	return resultTable{
		Columns:  meta,
		Rows:     outRows,
		RowCount: len(outRows),
	}, nil
}

func normalizeValue(v any) any {
	switch t := v.(type) {
	case nil:
		return nil
	case []byte:
		return string(t)
	case time.Time:
		return t.Format("2006-01-02 15:04:05")
	default:
		return t
	}
}
