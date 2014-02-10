from ._test_websocketserver import _test_server_create_start_stop, _test_server_echo


# nose won't find the tests if we import from another module, so we have to call them this way
def test_server_create_start_stop():
    _test_server_create_start_stop()


def test_server_echo():
    _test_server_echo()