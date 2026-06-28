package com.sqoptima.dba;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.sun.net.httpserver.Headers;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.stream.Collectors;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;

public final class DbaConnectorServer {
    private static final Gson GSON = new Gson();
    private static final int DEFAULT_PORT = 8742;
    private static final int QUERY_TIMEOUT_SECONDS = 120;
    private static final Map<String, ConnectionHolder> CONNECTIONS = new ConcurrentHashMap<>();

    public static void main(String[] args) throws Exception {
        ensureJdbcDrivers();

        int port = DEFAULT_PORT;
        for (int i = 0; i < args.length; i++) {
            if ("--port".equals(args[i]) && i + 1 < args.length) {
                port = Integer.parseInt(args[i + 1]);
            }
        }

        Path repoRoot = resolveRepoRoot();
        Path uiPath = resolveUiPath(repoRoot);

        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
        server.setExecutor(Executors.newCachedThreadPool());

        server.createContext("/api/ping", DbaConnectorServer::handlePing);
        server.createContext("/api/connect", DbaConnectorServer::handleConnect);
        server.createContext("/api/disconnect", DbaConnectorServer::handleDisconnect);
        server.createContext("/api/execute", DbaConnectorServer::handleExecute);
        server.createContext("/", exchange -> serveUi(exchange, uiPath));

        server.start();
        System.out.println("DBA Unified Connector running at http://127.0.0.1:" + port + "/");
        System.out.println("Press Ctrl+C to stop.");
    }

    private static void ensureJdbcDrivers() {
        loadDriver("org.postgresql.Driver", "PostgreSQL");
        loadDriver("com.microsoft.sqlserver.jdbc.SQLServerDriver", "SQL Server");
    }

    private static void loadDriver(String className, String label) {
        try {
            Class.forName(className);
            System.out.println("JDBC driver loaded: " + label);
        } catch (ClassNotFoundException ex) {
            throw new IllegalStateException("JDBC driver not found: " + label + " (" + className + ")", ex);
        }
    }

    private static Path resolveRepoRoot() {
        Path cwd = Path.of(System.getProperty("user.dir")).toAbsolutePath().normalize();
        if (Files.isDirectory(cwd.resolve("connection_libraries"))) {
            return cwd;
        }
        Path parent = cwd.getParent();
        if (parent != null && Files.isDirectory(parent.resolve("connection_libraries"))) {
            return parent;
        }
        return cwd;
    }

    private static Path resolveUiPath(Path repoRoot) {
        List<Path> candidates = List.of(
                repoRoot.resolve("DBA_Console.html"),
                repoRoot.resolve("unified_console/ui/DBA_Console.html"),
                Path.of(System.getProperty("user.dir")).resolve("DBA_Console.html")
        );
        for (Path candidate : candidates) {
            if (Files.exists(candidate)) {
                return candidate;
            }
        }
        return candidates.get(1);
    }

    private static void handlePing(HttpExchange exchange) throws IOException {
        if (!"GET".equals(exchange.getRequestMethod())) {
            sendJson(exchange, 405, Map.of("error", "Method not allowed"));
            return;
        }
        sendJson(exchange, 200, Map.of(
                "pong", true,
                "time", Instant.now().toString(),
                "connections", CONNECTIONS.keySet()
        ));
    }

    private static void handleConnect(HttpExchange exchange) throws IOException {
        if (!"POST".equals(exchange.getRequestMethod())) {
            sendJson(exchange, 405, Map.of("error", "Method not allowed"));
            return;
        }

        JsonObject body = GSON.fromJson(readBody(exchange), JsonObject.class);
        String engine = required(body, "engine").toLowerCase();
        long started = System.currentTimeMillis();

        try {
            Connection connection = openConnection(engine, body);
            String id = UUID.randomUUID().toString();
            ConnectionHolder holder = new ConnectionHolder(id, engine, connection, describe(connection, engine));
            CONNECTIONS.put(id, holder);

            Map<String, Object> response = new LinkedHashMap<>();
            response.put("success", true);
            response.put("connectionId", id);
            response.put("server", holder.info);
            response.put("durationMs", System.currentTimeMillis() - started);
            sendJson(exchange, 200, response);
            System.out.println("Connected [" + engine + "] " + holder.info.get("label"));
        } catch (Exception ex) {
            sendJson(exchange, 400, Map.of(
                    "success", false,
                    "error", ex.getMessage(),
                    "durationMs", System.currentTimeMillis() - started
            ));
            System.err.println("Connect failed: " + ex.getMessage());
        }
    }

    private static void handleDisconnect(HttpExchange exchange) throws IOException {
        if (!"POST".equals(exchange.getRequestMethod())) {
            sendJson(exchange, 405, Map.of("error", "Method not allowed"));
            return;
        }

        JsonObject body = GSON.fromJson(readBody(exchange), JsonObject.class);
        String id = required(body, "connectionId");
        ConnectionHolder removed = CONNECTIONS.remove(id);
        if (removed != null) {
            try {
                removed.connection.close();
            } catch (SQLException ignored) {
            }
        }
        sendJson(exchange, 200, Map.of("success", true));
    }

    private static void handleExecute(HttpExchange exchange) throws IOException {
        if (!"POST".equals(exchange.getRequestMethod())) {
            sendJson(exchange, 405, Map.of("error", "Method not allowed"));
            return;
        }

        JsonObject body = GSON.fromJson(readBody(exchange), JsonObject.class);
        String id = required(body, "connectionId");
        String sql = required(body, "sql");
        String database = optional(body, "database");
        ConnectionHolder holder = CONNECTIONS.get(id);
        if (holder == null) {
            sendJson(exchange, 400, Map.of("success", false, "error", "Not connected"));
            return;
        }

        long started = System.currentTimeMillis();
        List<Map<String, Object>> messages = new ArrayList<>();
        List<Map<String, Object>> tables = new ArrayList<>();

        try {
            if (database != null && !database.isBlank()) {
                holder.connection.setCatalog(database);
            }

            List<String> batches = splitSqlBatches(holder.engine, sql);
            if (batches.isEmpty()) {
                throw new IllegalArgumentException("No executable SQL after preprocessing");
            }

            try (Statement statement = holder.connection.createStatement()) {
                statement.setQueryTimeout(QUERY_TIMEOUT_SECONDS);
                int resultIndex = 0;

                for (String batch : batches) {
                    boolean hasResultSet = statement.execute(batch);
                    do {
                        if (hasResultSet) {
                            try (ResultSet rs = statement.getResultSet()) {
                                tables.add(resultSetToTable(rs, ++resultIndex));
                            }
                        } else {
                            int updateCount = statement.getUpdateCount();
                            if (updateCount != -1) {
                                messages.add(Map.of(
                                        "type", "update",
                                        "updateCount", updateCount,
                                        "index", ++resultIndex
                                ));
                            }
                        }
                        hasResultSet = statement.getMoreResults();
                    } while (hasResultSet || statement.getUpdateCount() != -1);
                }
            }

            sendJson(exchange, 200, Map.of(
                    "success", true,
                    "tables", tables,
                    "messages", messages,
                    "durationMs", System.currentTimeMillis() - started,
                    "tableCount", tables.size(),
                    "batchCount", batches.size()
            ));
        } catch (Exception ex) {
            sendJson(exchange, 400, Map.of(
                    "success", false,
                    "error", ex.getMessage(),
                    "durationMs", System.currentTimeMillis() - started
            ));
            System.err.println("Execute failed: " + ex.getMessage());
        }
    }

    private static List<String> splitSqlBatches(String engine, String sql) {
        if (sql == null || sql.isBlank()) {
            return List.of();
        }

        if ("mssql".equals(engine)) {
            return Arrays.stream(sql.split("(?im)^\\s*GO\\s*(?:\\s*--.*)?$"))
                    .map(String::trim)
                    .filter(batch -> !batch.isEmpty())
                    .collect(Collectors.toList());
        }

        if ("postgres".equals(engine)) {
            String cleaned = sql.lines()
                    .filter(line -> !line.trim().startsWith("\\"))
                    .collect(Collectors.joining("\n"))
                    .trim();
            return cleaned.isEmpty() ? List.of() : List.of(cleaned);
        }

        return List.of(sql.trim());
    }

    private static Connection openConnection(String engine, JsonObject body) throws SQLException {
        String host = required(body, "host").trim();
        if (host.isEmpty()) {
            throw new IllegalArgumentException("Host is required (e.g. localhost or your-server-name)");
        }
        String database = body.has("database") && !body.get("database").isJsonNull()
                ? body.get("database").getAsString()
                : ("postgres".equals(engine) ? "postgres" : "master");
        String username = optional(body, "username");
        String password = optional(body, "password");
        int port = body.has("port") && !body.get("port").isJsonNull()
                ? body.get("port").getAsInt()
                : ("postgres".equals(engine) ? 5432 : 1433);

        if ("postgres".equals(engine)) {
            String sslMode = optional(body, "sslMode");
            if (sslMode == null || sslMode.isBlank()) {
                sslMode = "prefer";
            }
            String url = String.format("jdbc:postgresql://%s:%d/%s?sslmode=%s", host, port, database, sslMode);
            Properties props = new Properties();
            if (username != null) {
                props.setProperty("user", username);
            }
            if (password != null) {
                props.setProperty("password", password);
            }
            return DriverManager.getConnection(url, props);
        }

        if ("mssql".equals(engine)) {
            boolean trustCertificate = !body.has("trustCertificate")
                    || body.get("trustCertificate").getAsBoolean();
            String encrypt = trustCertificate ? "true" : "true";
            String trust = trustCertificate ? "true" : "false";
            String url = String.format(
                    "jdbc:sqlserver://%s:%d;databaseName=%s;encrypt=%s;trustServerCertificate=%s",
                    host, port, database, encrypt, trust
            );
            Properties props = new Properties();
            if (username != null && !username.isBlank()) {
                props.setProperty("user", username);
                props.setProperty("password", password == null ? "" : password);
            } else {
                url += ";integratedSecurity=true";
            }
            return DriverManager.getConnection(url, props);
        }

        throw new IllegalArgumentException("Unsupported engine: " + engine);
    }

    private static Map<String, Object> describe(Connection connection, String engine) throws SQLException {
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("engine", engine);
        info.put("catalog", connection.getCatalog());
        try (Statement statement = connection.createStatement();
             ResultSet rs = statement.executeQuery(
                     "postgres".equals(engine) ? "SELECT version() AS version" : "SELECT @@VERSION AS version")) {
            if (rs.next()) {
                info.put("version", rs.getString(1));
            }
        }
        info.put("label", connection.getCatalog());
        return info;
    }

    private static Map<String, Object> resultSetToTable(ResultSet rs, int index) throws SQLException {
        ResultSetMetaData meta = rs.getMetaData();
        int columnCount = meta.getColumnCount();
        List<Map<String, String>> columns = new ArrayList<>();
        for (int i = 1; i <= columnCount; i++) {
            columns.add(Map.of(
                    "name", meta.getColumnLabel(i),
                    "type", meta.getColumnTypeName(i)
            ));
        }

        List<Map<String, Object>> rows = new ArrayList<>();
        while (rs.next()) {
            Map<String, Object> row = new LinkedHashMap<>();
            for (int i = 1; i <= columnCount; i++) {
                Object value = rs.getObject(i);
                row.put(meta.getColumnLabel(i), value);
            }
            rows.add(row);
        }

        Map<String, Object> table = new LinkedHashMap<>();
        table.put("index", index);
        table.put("columns", columns);
        table.put("rows", rows);
        table.put("rowCount", rows.size());
        return table;
    }

    private static void serveUi(HttpExchange exchange, Path uiPath) throws IOException {
        if (!"GET".equals(exchange.getRequestMethod())) {
            exchange.sendResponseHeaders(405, -1);
            return;
        }
        if (!Files.exists(uiPath)) {
            byte[] missing = ("UI not found: " + uiPath).getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "text/plain; charset=utf-8");
            exchange.sendResponseHeaders(404, missing.length);
            exchange.getResponseBody().write(missing);
            exchange.close();
            return;
        }
        byte[] bytes = Files.readAllBytes(uiPath);
        exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
        exchange.sendResponseHeaders(200, bytes.length);
        exchange.getResponseBody().write(bytes);
        exchange.close();
    }

    private static String readBody(HttpExchange exchange) throws IOException {
        try (InputStream in = exchange.getRequestBody()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private static void sendJson(HttpExchange exchange, int status, Object payload) throws IOException {
        addCors(exchange.getResponseHeaders());
        byte[] bytes = GSON.toJson(payload).getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(bytes);
        }
    }

    private static void addCors(Headers headers) {
        headers.set("Access-Control-Allow-Origin", "*");
        headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        headers.set("Access-Control-Allow-Headers", "Content-Type");
    }

    private static String required(JsonObject body, String key) {
        if (body == null || !body.has(key) || body.get(key).isJsonNull()) {
            throw new IllegalArgumentException("Missing required field: " + key);
        }
        String value = body.get(key).getAsString();
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Missing required field: " + key);
        }
        return value;
    }

    private static String optional(JsonObject body, String key) {
        if (body == null || !body.has(key) || body.get(key).isJsonNull()) {
            return null;
        }
        return body.get(key).getAsString();
    }

    private record ConnectionHolder(String id, String engine, Connection connection, Map<String, Object> info) {
    }
}
