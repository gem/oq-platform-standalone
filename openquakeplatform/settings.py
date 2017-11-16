"""
Django settings for oq_platform_standalone project.

For more information on this file, see
https://docs.djangoproject.com/en/1.6/topics/settings/

For the full list of settings and their values, see
https://docs.djangoproject.com/en/1.6/ref/settings/
"""
import os

WEBUIURL = 'http://localhost:8800/'

# Standalone flag to differentiate behaviors
STANDALONE = True

# If GEM_TIME_INVARIANT_OUTPUTS env variable is defined it means no
# time variant stuff inside output files
TIME_INVARIANT_OUTPUTS = ('GEM_TIME_INVARIANT_OUTPUTS' in os.environ)

# Build paths inside the project like this: os.path.join(BASE_DIR, ...)
BASE_DIR = os.path.dirname(os.path.dirname(__file__))

# Quick-start development settings - unsuitable for production
# See https://docs.djangoproject.com/en/1.6/howto/deployment/checklist/

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = 'klugdi+_!+e$dwvl!wy0uxi)gedje*l=*4@wv+%h#%0=hup%0f'

ALLOWED_HOSTS = ["localhost", "127.0.0.1"]

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = True

# This ugly hack is needed because in verifier.sh we are importing
# this file on the host and without Django installed to get INSTALLED_APPS
try:
    from django import get_version
    from distutils.version import StrictVersion

    if StrictVersion(get_version()) < StrictVersion('1.8'):
        # For backward compatibility with Django < 1.8
        # Be aware that names are different (template -> core)
        TEMPLATE_CONTEXT_PROCESSORS = (
            # 'django.contrib.auth.context_processors.auth',
            'django.core.context_processors.request',
            'django.core.context_processors.debug',
            'django.core.context_processors.i18n',
            'django.core.context_processors.media',
            'django.core.context_processors.static',
            'django.core.context_processors.tz',
            # 'django.contrib.messages.context_processors.messages',
            'openquakeplatform.utils.oq_context_processor',
        )
    else:
        TEMPLATES = [
            {
                'BACKEND': 'django.template.backends.django.DjangoTemplates',
                'APP_DIRS': True,
                'OPTIONS': {
                    'context_processors': [
                        # 'django.contrib.auth.context_processors.auth',
                        'django.template.context_processors.request',
                        'django.template.context_processors.debug',
                        'django.template.context_processors.i18n',
                        'django.template.context_processors.media',
                        'django.template.context_processors.static',
                        'django.template.context_processors.tz',
                        # 'django.contrib.messages.context_processors.messages',
                        'openquakeplatform.utils.oq_context_processor',
                    ],
                },
            },
        ]
except ImportError:
    pass

# Application definition
INSTALLED_APPS = (
    # 'django.contrib.admin',
    # 'django.contrib.auth',
    # 'django.contrib.contenttypes',
    # 'django.contrib.sessions',
    # 'django.contrib.messages',
    'django.contrib.staticfiles',

    'openquakeplatform',
)

# To be compliant the app must have
# a 'header_info' class with title field
# defined in __init__.py base
#
# I.E.
# header_info = { "title": "IPT" }

# To develop single apps add a line like:
# STANDALONE_APPS = ('openquakeplatform_ipt',)
# in your local_settings.py
STANDALONE_APPS = (
    'openquakeplatform_ipt',
    'openquakeplatform_taxtweb',
#    'openquakeplatform_taxonomy',
)

MIDDLEWARE_CLASSES = (
    'django.middleware.common.CommonMiddleware',
    # 'django.contrib.sessions.middleware.SessionMiddleware',
    # 'django.middleware.csrf.CsrfViewMiddleware',
    # 'django.contrib.auth.middleware.AuthenticationMiddleware',
    # 'django.contrib.messages.middleware.MessageMiddleware',
    # 'django.middleware.clickjacking.XFrameOptionsMiddleware',
)

ROOT_URLCONF = 'openquakeplatform_server.urls'

WSGI_APPLICATION = 'openquakeplatform_server.wsgi.application'

FILE_PATH_FIELD_DIRECTORY = os.path.join(os.path.expanduser('~'), 'oqdata')

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': os.path.join(FILE_PATH_FIELD_DIRECTORY,
                             'platform-standalone.sqlite3'),
    }
}

# Internationalization
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_L10N = True
USE_TZ = True

# Static files (CSS, JavaScript, Images)
STATIC_URL = '/static/'

try:
    from local_settings import *
except ImportError:
    pass

INSTALLED_APPS += STANDALONE_APPS
