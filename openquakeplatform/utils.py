from django.conf import settings
from importlib import import_module

try:
    # Django 2.0+
    from django.urls import reverse
except ImportError:
    from django.core.urlresolvers import reverse


def oq_is_qgis_browser(request):
    for k in request.META:
        if k.startswith('HTTP_GEM__QGIS_'):
            return True
    return False


def oq_context_processor(request):
    """
    A custom context processor which allows injection of additional
    context variables.
    """

    app_name_map = {
        'openquakeplatform_ipt': 'ipt',
        'openquakeplatform_taxonomy': 'glossary',
        'django_gem_taxonomy': 'taxonomy'
    }

    context = {}

    context['app_list'] = []

    cl_list = ['calc', 'share', 'explore']
    for ct, app_full in enumerate(settings.STANDALONE_APPS):
        app = app_full.split('.')[0]
        # remove 'openquakeplatform_' suffix with slicing
        if app in app_name_map:
            app_name = app_name_map[app]
        else:
            app_name = app[18:]
        appmod = import_module(app, 'header_info')
        appmod.header_info['url'] = reverse(app_name + ':home')
        appmod.header_info['class'] = cl_list[ct % 3]
        context['app_list'].append(appmod.header_info)

    if oq_is_qgis_browser(request):
        context['gem_qgis'] = True

    return context
