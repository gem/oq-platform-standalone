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

    context = {}

    context['app_list'] = []

    cl_list = ['calc', 'share', 'explore']
    for ct, app in enumerate(settings.STANDALONE_APPS):
        # remove 'openquakeplatform_' suffix with slicing
        app_name = app[18:]
        appmod = import_module(app, 'header_info')
        appmod.header_info['url'] = reverse(app_name + ':home')
        appmod.header_info['class'] = cl_list[ct % 3]
        context['app_list'].append(appmod.header_info)

    context['gem_qgis'] = oq_is_qgis_browser(request)

    return context
