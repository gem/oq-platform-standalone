from django.conf.urls import include, url

from openquakeplatform.settings import STANDALONE_APPS
from django.contrib import admin
from django.views.generic import TemplateView

# Uncomment the following line to enable admin
# admin.autodiscover()

urlpatterns = [
    # Uncomment the following line to enable admin
    # url(r'^admin/', include(admin.site.urls)),
]

for app in STANDALONE_APPS:
    # STANDALONE_APPS format is openquakeplatform_appname
    # app_name is made by the token after '_' and used for suburl and namespace
    app_name = app.split('_')[1]
    urlpatterns.append(url(r'^%s/' % app_name, include('%s.urls' % app,
                       namespace='%s' % app_name)))
