from openquake.moon import Moon

pla = Moon()
pla.primary_set()

def setup_package():
    pla.init(autologin=False)

def teardown_package():
    pla.fini()
