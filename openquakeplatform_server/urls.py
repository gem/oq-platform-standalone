from django.conf.urls import patterns, include, url

from settings import STANDALONE_APPS
from django.contrib import admin
from django.views.generic import TemplateView


js_info_dict = {
    'domain': 'djangojs',
    'packages': ('geonode',)
}

admin.autodiscover()

urlpatterns = patterns(
    '',
    url(r'^lang\.js$',
        TemplateView.as_view(template_name='lang.js',
                             content_type='text/javascript'),
        name='lang'),
    url(r'^jsi18n/$', 'django.views.i18n.javascript_catalog',
        js_info_dict, name='jscat'),
    (r'^i18n/', include('django.conf.urls.i18n')),

    url(r'^admin/', include(admin.site.urls)),
)

for app in STANDALONE_APPS:
    # STANDALONE_APPS format is openquakeplatform_appname
    # app_name is made by the token after '_' and used for suburl and namespace
    app_name = app.split('_')[1]
    urlpatterns += patterns('',
                            url(r'^%s/' % app_name, include('%s.urls' % app,
                                namespace='%s' % app_name)))
