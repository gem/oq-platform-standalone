import re
import unittest
from inspect import isclass

_setup_module_list = []
_teardown_module_list = []


def setup_module(module):
    for f in _setup_module_list:
        f(module)


def teardown_module(module):
    for f in _teardown_module_list:
        f(module)


def import_by_name(dotname):
    components = dotname.split('.')
    leaf = components[-1]
    mod = __import__(dotname, fromlist=[leaf])
    return mod


def get_checks(pkgname):
    global _setup_module_list, _teardown_module_list

    cls = import_by_name(pkgname)
    for objname in dir(cls):
        obj = getattr(cls, objname)
        if isclass(obj) and issubclass(obj, unittest.TestCase):
            newname = re.sub('^openquakeplatform_', '',
                             "%s__%s" % (pkgname.replace('.', '__'), objname))
            newname = re.sub('__test__', '__', newname, 1)
            globals()[newname] = obj
            obj.__name__ = newname
        elif callable(obj) is True:
            if objname == 'setup_module':
                _setup_module_list.append(obj)
            elif objname == 'teardown_module':
                _teardown_module_list.append(obj)


for pkgname in ['openquakeplatform_ipt.test',
                'openquakeplatform_taxtweb.test']:
    try:
        get_checks(pkgname)
    except ImportError:
        print("Package [%s] NOT FOUND" % pkgname)
        pass
