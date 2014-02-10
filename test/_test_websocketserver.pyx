import threading
from posix.unistd cimport usleep

from examples.websocketserver import WebSocketServer


PORT = 9091


def _test_server_create_start_stop():
    server = WebSocketServer(PORT)
    thread = threading.Thread(target=server.run)
    thread.start()
    usleep(100)
    server.stop()
    thread.join()


def _test_server_echo():
    from tornado import ioloop
    server = WebSocketServer(PORT)
    server_thread = threading.Thread(target=server.run)
    server_thread.start()

    from ws4py.client.tornadoclient import TornadoWebSocketClient
    class DummyClient(TornadoWebSocketClient):
        def opened(self):
            for i in range(10):
                print('client sending %s' % i)
                self.send('%s' % i)

        def closed(self, code, reason=None):
            print("Closed down", code, reason)

        def received_message(self, m):
            print('client received %s' % unicode(m))
            if len(m) == 175:
                self.close(reason='Bye bye')

    def client():
        try:
            ws = DummyClient('ws://0.0.0.0:%s/' % PORT, protocols=['http-only', 'chat'])
            ws.connect()
            ioloop.IOLoop.instance().start()
        except KeyboardInterrupt:
            ws.close()

    client_thread = threading.Thread(target=client)
    client_thread.start()

    client_thread.join()
    server.stop()
    server_thread.join()
