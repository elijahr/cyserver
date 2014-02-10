
from distutils.core import setup
from cyserver.config import make_setup_args, ext_modules_dict


setup_args = make_setup_args(ext_modules=list(ext_modules_dict.values()))


if __name__ == '__main__':
    setup(**setup_args)