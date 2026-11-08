"""Loopback-only protocol fixtures. Prints port and counts, never application data."""
import socket
import struct
import sys
import ssl

mode = sys.argv[1]
server = socket.socket()
server.bind(('127.0.0.1', 0))
server.listen(1)
server.settimeout(15)
print(server.getsockname()[1], flush=True)
client, _ = server.accept()
client.settimeout(8)

def read(count):
    data = b''
    while len(data) < count:
        block = client.recv(count - len(data))
        if not block:
            raise EOFError()
        data += block
    return data

try:
    if mode.startswith('vnc'):
        client.sendall(b'RFB 003.008\n')
        read(12)
        client.sendall(b'\x01\x01')
        assert read(1) == b'\x01'
        client.sendall(struct.pack('!I', 0))
        read(1)
        pixel_format = struct.pack('!BBBBHHHBBB3x', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
        name_length = 0xffffffff if mode == 'vnc-huge-name' else 7
        client.sendall(struct.pack('!HH', 32, 32) + pixel_format + struct.pack('!I', name_length) + (b'' if mode == 'vnc-huge-name' else b'Fixture'))
        sent_frame = False
        while True:
            kind = read(1)[0]
            if kind == 0:
                read(19)
            elif kind == 2:
                header = read(3)
                read(struct.unpack('!H', header[1:])[0] * 4)
            elif kind == 3:
                read(9)
                if not sent_frame:
                    if mode == 'vnc-huge-zlib':
                        client.sendall(b'\x00\x00\x00\x01' + struct.pack('!HHHHiI', 0, 0, 32, 32, 6, 0xffffffff))
                    else:
                        client.sendall(b'\x00\x00\x00\x01' + struct.pack('!HHHHi', 0, 0, 32, 32, 0) + b'\x30\x80\xb0\x00' * (32 * 32))
                    if mode == 'vnc-bad-clipboard':
                        client.sendall(b'\x03\x00\x00\x00\x80\x00\x00\x00')
                    sent_frame = True
                    print('FRAME_SENT', flush=True)
            elif kind == 4:
                read(7)
            elif kind == 5:
                read(5)
            else:
                raise AssertionError('Unexpected message; clipboard sharing must be off')
    elif mode == 'rdp-untrusted':
        length = struct.unpack('!H', read(4)[2:])[0]
        read(length - 4)
        client.sendall(bytes.fromhex('030000130ed000000000000200080001000000'))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(sys.argv[2], sys.argv[3])
        client = context.wrap_socket(client, server_side=True)
        data = client.recv(4096)
        print('APPLICATION_BYTES:' + str(len(data)), flush=True)
except (EOFError, ConnectionError, OSError, ssl.SSLError):
    pass
finally:
    client.close()
    server.close()
