#!/usr/bin/env python3
"""
Clipboard Sync Server - PC side
Shares clipboard with iOS jailbreak tweak over LAN.

Usage:
    python3 clipboard_server.py
    python3 clipboard_server.py --port 8888
    python3 clipboard_server.py --host 0.0.0.0 --port 9527
"""

import socket
import threading
import json
import time
import hashlib
import sys
import argparse

try:
    import pyperclip
except ImportError:
    print("[ERROR] pyperclip not installed. Run: pip install pyperclip")
    sys.exit(1)

BUFFER_SIZE = 4096


class ClipboardServer:
    def __init__(self, host="0.0.0.0", port=9527):
        self.host = host
        self.port = port
        self.clients = []
        self.lock = threading.Lock()
        self.last_hash = ""
        self.running = True
        self.from_network = False

    def _get_clipboard(self):
        try:
            text = pyperclip.paste()
            return text
        except Exception:
            return ""

    def _set_clipboard(self, text):
        try:
            self.from_network = True
            pyperclip.copy(text)
            self.last_hash = self._hash(text)
            self.from_network = False
        except Exception as e:
            print(f"[ERROR] Failed to set clipboard: {e}")

    def _hash(self, text):
        return hashlib.md5(text.encode("utf-8", errors="ignore")).hexdigest()

    def _broadcast(self, message, exclude=None):
        with self.lock:
            dead = []
            for client in self.clients:
                if client is exclude:
                    continue
                try:
                    client.sendall(message)
                except Exception:
                    dead.append(client)
            for client in dead:
                self.clients.remove(client)

    def _handle_client(self, sock, address):
        print(f"[+] Client connected: {address[0]}:{address[1]}")
        with self.lock:
            self.clients.append(sock)

        buf = ""
        try:
            while self.running:
                data = sock.recv(BUFFER_SIZE)
                if not data:
                    break
                buf += data.decode("utf-8", errors="ignore")
                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    self._process_message(line, sock)
        except Exception as e:
            print(f"[-] Client error: {e}")
        finally:
            print(f"[-] Client disconnected: {address[0]}:{address[1]}")
            with self.lock:
                if sock in self.clients:
                    self.clients.remove(sock)
            try:
                sock.close()
            except Exception:
                pass

    def _process_message(self, line, sock):
        line = line.strip()
        if not line:
            return
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            return

        cmd = msg.get("cmd", "")
        if cmd == "set":
            text = msg.get("text", "")
            if text:
                self._set_clipboard(text)
        elif cmd == "ping":
            try:
                sock.sendall(b'{"cmd":"pong"}\n')
            except Exception:
                pass

    def _monitor_clipboard(self):
        while self.running:
            time.sleep(0.5)
            if self.from_network:
                continue

            text = self._get_clipboard()
            h = self._hash(text) if text else ""
            if h and h != self.last_hash:
                self.last_hash = h
                msg = json.dumps({"cmd": "set", "text": text}) + "\n"
                data = msg.encode("utf-8")
                self._broadcast(data)

    def start(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.host, self.port))
        server.listen(5)

        print("=" * 50)
        print(f"  Clipboard Sync Server")
        print(f"  Listening on {self.host}:{self.port}")
        print(f"  Set this IP on your iOS device settings")
        print("=" * 50)
        print("Waiting for iOS device connection...")
        print("Press Ctrl+C to stop\n")

        monitor = threading.Thread(target=self._monitor_clipboard, daemon=True)
        monitor.start()

        try:
            while self.running:
                try:
                    client, addr = server.accept()
                except Exception:
                    break
                t = threading.Thread(target=self._handle_client,
                                     args=(client, addr), daemon=True)
                t.start()
        except KeyboardInterrupt:
            print("\nShutting down...")
        finally:
            self.running = False
            monitor.join(timeout=1)
            server.close()
            print("Server stopped.")


def main():
    parser = argparse.ArgumentParser(description="Clipboard Sync Server")
    parser.add_argument("--host", default="0.0.0.0",
                        help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=9527,
                        help="Port number (default: 9527)")
    args = parser.parse_args()

    srv = ClipboardServer(host=args.host, port=args.port)
    srv.start()


if __name__ == "__main__":
    main()
