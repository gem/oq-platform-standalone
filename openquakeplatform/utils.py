from django.conf import settings
from django.core.urlresolvers import reverse
from importlib import import_module


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

    for k in request.META:
        if k.startswith('HTTP_GEM__QGIS'):
            context['gem_qgis'] = True
            break

    return context
