from distutils.command.build_clib import build_clib
import os

from Cython.Distutils import build_ext
from Cython.Build import cythonize


cyserver_project_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

build_dir = os.path.join(cyserver_project_dir, 'build')

cyserver_package_dir = os.path.join(cyserver_project_dir, 'cyserver')

include_dirs = [
    os.path.join(cyserver_project_dir, 'include'),
    os.path.join(cyserver_project_dir, 'include', 'libev'),
    os.path.join(cyserver_project_dir, 'include', 'hmac_sha1')
]

libraries_dict = {
    'http_parser': {'sources': [os.path.join(cyserver_project_dir, 'include', 'http-parser', 'http_parser.c')]},
    'ev': {'sources': [os.path.join(cyserver_project_dir, 'include', 'libev', 'ev.c')]},
    'hmac_sha1': {'sources': [
        os.path.join(cyserver_project_dir, 'include', 'hmac_sha1', 'sha1.c'),
        os.path.join(cyserver_project_dir, 'include', 'hmac_sha1', 'hmac.c'),
        os.path.join(cyserver_project_dir, 'include', 'hmac_sha1', 'hmac_sha1.c'),
    ]}
}
libraries = list(libraries_dict.items())


def make_ext_modules(module_dirs):
    ext_modules = cythonize(module_dirs, nthreads=0, include_path=include_dirs)

    for module in ext_modules:
        module.extra_compile_args = ['-O3']

    ext_modules_dict = dict([(module.name, module) for module in ext_modules])

    return ext_modules_dict


ext_modules_dict = make_ext_modules([
    os.path.join(cyserver_project_dir, 'cyserver', '*.pyx'),
])

ext_modules_dict['cyserver.hmac_sha1'].sources += libraries_dict['hmac_sha1']['sources']

ext_modules_dict['cyserver.libev'].sources += libraries_dict['ev']['sources']
ext_modules_dict['cyserver.libev'].extra_link_args = ['-static']

ext_modules_dict['cyserver.http_parser'].sources += libraries_dict['http_parser']['sources']
ext_modules_dict['cyserver.http_parser'].extra_link_args = ['-static']


def make_setup_args(package_name='cyserver', **kwargs):
    setup_args = dict(name=package_name,
                      cmdclass=dict(build_ext=build_ext, build_clib=build_clib),
                      packages=[package_name],
                      include_dirs=include_dirs)
    setup_args.update(kwargs)
    return setup_args