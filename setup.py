import os
from setuptools import setup
from openquakeplatform import __version__

with open(os.path.join(os.path.dirname(__file__), 'README.md')) as readme:
    README = readme.read()

# allow setup.py to be run from any path
os.chdir(os.path.normpath(os.path.join(os.path.abspath(__file__), os.pardir)))

setup(
    name='oq-platform-standalone',
    version=__version__,
    # packages=find_packages(),
    packages=["openquakeplatform"],
    include_package_data=True,
    license="AGPL3",
    description='Standalone replacements for OpenQuake Platform.',
    long_description=README,
    url='http://github.com/gem/oq-platform-standalone',
    author='GEM Foundation',
    author_email='devops@openquake.org',
    install_requires=[
        'django >=1.5, <2.3',
        'numpy<1.20,>=1.18',
    ],
    classifiers=[
        'Environment :: Web Environment',
        'Framework :: Django',
        'Intended Audience :: Scientists',
        'License :: OSI Approved :: AGPL3',
        'Operating System :: OS Independent',
        'Programming Language :: Python',
        'Programming Language :: Python :: 2',
        'Programming Language :: Python :: 2.7',
        'Topic :: Internet :: WWW/HTTP',
        'Topic :: Internet :: WWW/HTTP :: Dynamic Content',
    ],
)
