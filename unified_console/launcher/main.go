// DBA-Console native launcher — double-click to start connector and open browser.
package main

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"
)

const defaultPort = "8742"

func main() {
	base, err := appBaseDir()
	if err != nil {
		fail("resolve app directory: %v", err)
	}

	port := envOr("DBA_CONSOLE_PORT", defaultPort)
	jar, err := findJar(base)
	if err != nil {
		fail("%v", err)
	}

	java, err := findJava(base)
	if err != nil {
		fail("%v", err)
	}

	workDir := findWorkDir(base)

	cmd := exec.Command(java, "-jar", jar, "--port", port)
	cmd.Dir = workDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		fail("start connector: %v", err)
	}

	url := fmt.Sprintf("http://127.0.0.1:%s/", port)
	if err := waitForPort(port, 15*time.Second); err != nil {
		_ = cmd.Process.Kill()
		fail("connector did not start: %v", err)
	}

	if err := openBrowser(url); err != nil {
		fmt.Fprintf(os.Stderr, "Open browser manually: %s\n", url)
	}

	fmt.Printf("DBA Console running at %s\n", url)
	fmt.Println("Close this window to stop the connector.")

	if err := cmd.Wait(); err != nil {
		os.Exit(1)
	}
}

func appBaseDir() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.Dir(exe), nil
}

func findJar(base string) (string, error) {
	candidates := []string{
		filepath.Join(base, "dba-connector-1.0.0.jar"),
		filepath.Join(base, "..", "connector", "target", "dba-connector-1.0.0.jar"),
		filepath.Join(base, "..", "..", "unified_console", "connector", "target", "dba-connector-1.0.0.jar"),
	}
	for _, c := range candidates {
		if fileExists(c) {
			return filepath.Clean(c), nil
		}
	}
	return "", fmt.Errorf("connector JAR not found (build with: mvn -f unified_console/connector/pom.xml package)")
}

func findWorkDir(base string) string {
	candidates := []string{
		base,
		filepath.Join(base, ".."),
		filepath.Join(base, "..", ".."),
	}
	for _, c := range candidates {
		c = filepath.Clean(c)
		if dirExists(filepath.Join(c, "connection_libraries")) {
			return c
		}
	}
	return filepath.Clean(base)
}

func findJava(base string) (string, error) {
	candidates := []string{
		filepath.Join(base, "runtime", "bin", "java"),
		filepath.Join(base, "runtime", "bin", "java.exe"),
		filepath.Join(base, "..", "dist", "DBA-Console-Portable", "runtime", "bin", "java"),
		filepath.Join(base, "..", "dist", "DBA-Console-Portable", "runtime", "bin", "java.exe"),
	}
	if runtime.GOOS == "windows" {
		candidates = append([]string{
			filepath.Join(base, "runtime", "bin", "java.exe"),
		}, candidates...)
	}

	for _, c := range candidates {
		c = filepath.Clean(c)
		if fileExists(c) {
			return c, nil
		}
	}

	if path, err := exec.LookPath("java"); err == nil {
		return path, nil
	}

	return "", fmt.Errorf("Java runtime not found — build portable bundle or install JDK 21+")
}

func waitForPort(port string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp", "127.0.0.1:"+port, 300*time.Millisecond)
		if err == nil {
			_ = conn.Close()
			return nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	return fmt.Errorf("timed out waiting for port %s", port)
}

func openBrowser(url string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	case "darwin":
		cmd = exec.Command("open", url)
	default:
		if _, err := exec.LookPath("xdg-open"); err == nil {
			cmd = exec.Command("xdg-open", url)
		} else {
			return fmt.Errorf("xdg-open not found")
		}
	}
	return cmd.Start()
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "DBA Console: "+format+"\n", args...)
	os.Exit(1)
}
