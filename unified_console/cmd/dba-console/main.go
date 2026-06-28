package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"
)

const defaultPort = 8742

func main() {
	port := flag.Int("port", defaultPort, "HTTP listen port")
	noBrowser := flag.Bool("no-browser", false, "do not open browser on start")
	flag.Parse()

	base, err := appBaseDir()
	if err != nil {
		fail("app directory: %v", err)
	}

	uiPath, err := resolveUIPath(base)
	if err != nil {
		fail("%v", err)
	}

	srv := newServer(uiPath)
	addr := fmt.Sprintf("127.0.0.1:%d", *port)

	go func() {
		log.Printf("DBA Console running at http://%s/", addr)
		if err := srv.listen(addr); err != nil {
			fail("server: %v", err)
		}
	}()

	if err := waitForPort(*port, 15*time.Second); err != nil {
		fail("startup: %v", err)
	}

	url := fmt.Sprintf("http://127.0.0.1:%d/", *port)
	if !*noBrowser {
		if err := openBrowser(url); err != nil {
			fmt.Fprintf(os.Stderr, "Open browser manually: %s\n", url)
		}
	}

	fmt.Printf("DBA Console ready at %s\n", url)
	fmt.Println("Close this window to stop.")

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	_ = srv.shutdown()
}

func appBaseDir() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.Dir(exe), nil
}

func resolveUIPath(base string) (string, error) {
	candidates := []string{
		filepath.Join(base, "DBA_Console.html"),
		filepath.Join(base, "..", "ui", "DBA_Console.html"),
		filepath.Join(base, "..", "..", "unified_console", "ui", "DBA_Console.html"),
	}
	for _, c := range candidates {
		c = filepath.Clean(c)
		if fileExists(c) {
			return c, nil
		}
	}
	return "", fmt.Errorf("DBA_Console.html not found next to executable")
}

func waitForPort(port int, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	addr := fmt.Sprintf("127.0.0.1:%d", port)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp", addr, 300*time.Millisecond)
		if err == nil {
			_ = conn.Close()
			return nil
		}
		time.Sleep(150 * time.Millisecond)
	}
	return fmt.Errorf("timed out waiting for port %d", port)
}

func openBrowser(url string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	case "darwin":
		cmd = exec.Command("open", url)
	default:
		if _, err := exec.LookPath("xdg-open"); err != nil {
			return err
		}
		cmd = exec.Command("xdg-open", url)
	}
	return cmd.Start()
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "DBA Console: "+format+"\n", args...)
	os.Exit(1)
}
