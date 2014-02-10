import os
import pyximport
from cyserver import config

config.ext_modules_dict.update(config.make_ext_modules([
    os.path.join(config.cyserver_project_dir, 'examples', '*.pyx'),
    os.path.join(config.cyserver_project_dir, 'test', '*.pyx'),
]))

pyximport.install(load_py_module_on_import_failure=True,
                  build_dir=config.build_dir,
                  setup_args=config.make_setup_args())

