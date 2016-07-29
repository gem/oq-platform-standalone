#!/bin/bash
#
# packager.sh  Copyright (c) 2015, GEM Foundation.
#
# OpenQuake is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# OpenQuake is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with OpenQuake.  If not, see <http://www.gnu.org/licenses/>.

#
# DESCRIPTION
#
# verifier.sh automates procedures to:
#  - test development environment
#  - TODO test production environment
#
# tests are performed inside linux containers (lxc) to achieve
# a good compromise between speed and isolation
#
# all lxc instances are ephemeral
#
# ephemeral containers are "clones" of a base container and have a
# temporary file system that reflects the contents of the base container
# but any modifications are stored in another overlayed
# file system (in-memory or disk)
#

# INSTALL A PLATFORM ON A BAREBONES UBUNTU MACHINE
# you can use verifier.sh to install a permanent LXC machine
#
# to do it:
#
# - copy openquakeplatform/bin/lxc-* to your /usr/local/sbin
#
# - set these env variables (change <lxc-machine-name> with your m. name)
#
# export GEM_EPHEM_IP_GET=lxc-ip-get-gem
# export GEM_EPHEM_NAME=<lxc-machine-name>
# export GEM_EPHEM_DESTROY=echo lxc-destroy-fake
# export GEM_EPHEM_CMD=lxc-start-gem
#
# run ./verifier.sh prodtest <your-branch-name>



# MAYBE GOOD FOR PRODUCTION TEST PART
# sudo apt-get install git
# git clone --depth 1 -b ci-test1 https://github.com/gem/oq-platform.git
# sudo sed -i  's/127.0.1.1   \+\([^ ]\+\)/127.0.1.1   \1 \1.gem.lan/g'  /etc/hosts
# # get name from hosts
# hname=...
be# sed -i 's/127.0.1.1   \+\([^ ]\+\)/127.0.1.1   \1 \1.gem.lan/g'  /etc/hosts
# echo -e "y\ny\ny\n" | ./oq-platform/openquakeplatform/bin/deploy.sh -H $hname

# export PS4='+${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
if [ $GEM_SET_DEBUG ]; then
    set -x
fi
set -e
GEM_GIT_REPO="git://github.com/gem"
GEM_GIT_PACKAGE="oq-platform-standalone"
GEM_DEB_PACKAGE="python-${GEM_GIT_PACKAGE}"
GEM_DEB_SERIE="master"
if [ -z "$GEM_DEB_REPO" ]; then
    GEM_DEB_REPO="$HOME/gem_ubuntu_repo"
fi
if [ -z "$GEM_DEB_MONOTONE" ]; then
    GEM_DEB_MONOTONE="$HOME/monotone"
fi

GEM_BUILD_ROOT="build-deb"
GEM_BUILD_SRC="${GEM_BUILD_ROOT}/${GEM_DEB_PACKAGE}"

GEM_MAXLOOP=20

GEM_ALWAYS_YES=false

if [ "$GEM_EPHEM_CMD" = "" ]; then
    GEM_EPHEM_CMD="lxc-start-ephemeral"
fi
if [ "$GEM_EPHEM_NAME" = "" ]; then
    GEM_EPHEM_NAME="ubuntu14-x11-lxc-eph"
fi

LXC_VER=$(lxc-ls --version | cut -d '.' -f 1)

if [ $LXC_VER -lt 1 ]; then
    echo "lxc >= 1.0.0 is required." >&2
    exit 1
fi

LXC_TERM="lxc-stop -t 10"
LXC_KILL="lxc-stop -k"

if command -v lxc-copy &> /dev/null; then
    # New lxc (>= 2.0.0) with lxc-copy
    GEM_EPHEM_EXE="${GEM_EPHEM_CMD} -n ${GEM_EPHEM_NAME} -e"
else
    # Old lxc (< 2.0.0) with lxc-start-ephimeral
    GEM_EPHEM_EXE="${GEM_EPHEM_CMD} -o ${GEM_EPHEM_NAME} -d"
fi

if [ "$GEM_EPHEM_DESTROY" != "" ]; then
    LXC_DESTROY="$GEM_EPHEM_DESTROY"
else
    LXC_DESTROY="lxc-destroy"
fi

ACTION="none"

NL="
"
TB="	"

#
#  remote init files
cat >.gem_init.sh <<EOF
export GEM_SET_DEBUG=$GEM_SET_DEBUG
set -e
if [ -n "\$GEM_SET_DEBUG" -a "\$GEM_SET_DEBUG" != "false" ]; then
    export PS4='+\${BASH_SOURCE}:\${LINENO}:\${FUNCNAME[0]}: '
    set -x
fi
source .gem_ffox_init.sh
EOF

cat >.gem_ffox_init.sh <<EOF
export GEM_FIREFOX_ON_HOLD=$GEM_FIREFOX_ON_HOLD
if [ "\$GEM_FIREFOX_ON_HOLD" ]; then
    sudo apt-mark hold firefox firefox-locale-en
else
    sudo apt-get update
    ffox_pol="\$(apt-cache policy firefox)"
    ffox_cur="\$(echo "\$ffox_pol" | grep '^  Installed:' | sed 's/.*: //g')"
    ffox_can="\$(echo "\$ffox_pol" | grep '^  Candidate:' | sed 's/.*: //g')"

    if [ "\$ffox_cur" != "\$ffox_can" ]; then
        echo "WARNING: firefox has been upgraded, run it to accomplish update operations"
        sudo apt-get -y upgrade
        sudo apt-get -y install wmctrl
        export DISPLAY=:1
        firefox &
        ffox_pid=\$!
        st="none"
        for i in \$(seq 1 1000) ; do
            ffox_wins="\$(wmctrl -l | grep -i "firefox" || true)"
            if [ "\$st" = "none" ]; then
                if echo "\$ffox_wins" | grep -qi 'update'; then
                    st="update"
                elif echo "\$ffox_wins" | grep -qi 'mozilla'; then
                    break
                fi
            elif [ "\$st" = "update" ]; then
                if echo "\$ffox_wins" | grep -qvi 'update'; then
                    break
                fi
            fi
            sleep 0.02
        done
        kill \$ffox_pid || true
        sleep 2
    fi
fi
EOF

#
#  functions
copy_common () {
    scp "${lxc_ip}:ssh.log" "out/${1}_ssh_history.log" || true
    scp "${lxc_ip}:.pip/pip.log" "out/${1}_pip_history.log" || true
}

copy_dev () {
    scp "${lxc_ip}:$GEM_GIT_PACKAGE/openquakeplatform/bootstrap.log" "out/dev_bootstrap.log" || true
    scp "${lxc_ip}:$GEM_GIT_PACKAGE/openquakeplatform/xunit-platform-dev.xml" "out/" || true
    scp "${lxc_ip}:$GEM_GIT_PACKAGE/openquakeplatform/dev_*.png" "out/" || true
    scp "${lxc_ip}:$GEM_GIT_PACKAGE/openquakeplatform/runserver.log" "out/dev_runserver.log" || true
    scp "${lxc_ip}:$GEM_GIT_PACKAGE/openquakeplatform/openquakeplatform/local_settings.py" "out/dev_local_settings.py" || true
}

copy_prod () {
    scp "${lxc_ip}:/var/log/apache2/access.log" "out/prod_apache2_access.log" || true
    scp "${lxc_ip}:/var/log/apache2/error.log" "out/prod_apache2_error.log" || true
    scp "${lxc_ip}:/var/log/tomcat7/catalina.out" "out/prod_tomcat7_catalina.log" || true
    scp "${lxc_ip}:$GEM_GIT_PACKAGE/openquakeplatform/xunit-platform-prod.xml" "out/" || true
    scp "${lxc_ip}:$GEM_GIT_PACKAGE/openquakeplatform/prod_*.png" "out/" || true
    scp "${lxc_ip}:/etc/openquake/platform/local_settings.py" "out/prod_local_settings.py" || true
}

#
#  sig_hand - manages cleanup if the build is aborted
#
sig_hand () {
    trap ERR
    echo "signal trapped"
    if [ "$lxc_name" != "" ]; then
        set +e
        ssh -t  $lxc_ip "cd ~/$GEM_GIT_PACKAGE; . platform-env/bin/activate ; cd openquakeplatform ; sleep 5 ; fab stop"

        copy_common "$ACTION"
        copy_dev
        copy_prod

        echo "Destroying [$lxc_name] lxc"
        if [ "$LXC_DESTROY" = "lxc-destroy" ]; then
            upper="$(mount | grep "${lxc_name}.*upperdir" | sed 's@.*upperdir=@@g;s@,.*@@g')"
            if [ -f "${upper}.dsk" ]; then
                loop_dev="$(sudo losetup -a | grep "(${upper}.dsk)$" | cut -d ':' -f1)"
            fi
            sudo $LXC_KILL -n $lxc_name
            sudo umount /var/lib/lxc/$lxc_name/rootfs
            sudo umount /var/lib/lxc/$lxc_name/ephemeralbind
            echo "$upper" | grep -q '^/tmp/'
            if [ $? -eq 0 ]; then
                sudo umount "$upper"
                sudo rm -r "$upper"
                if [ "$loop_dev" != "" ]; then
                    sudo losetup -d "$loop_dev"
                    if [ -f "${upper}.dsk" ]; then
                        sudo rm -f "${upper}.dsk"
                    fi
                fi
            fi
        fi
        sudo $LXC_DESTROY -n $lxc_name
    fi
    if [ -f /tmp/packager.eph.$$.log ]; then
        rm /tmp/packager.eph.$$.log
    fi
}


#
#  dep2var <dep> - converts in a proper way the name of a dependency to a variable name
#      <dep>    the name of the dependency
#
dep2var () {
    echo "$1" | sed 's/[-.]/_/g;s/\(.*\)/\U\1/g'
}

#
#  repo_id_get - retry git repo from local git remote command
repo_id_get () {
    local repo_name repo_line

    if ! repo_name="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)"; then
        repo_line="$(git remote -vv | grep "^origin[ ${TB}]" | grep '(fetch)$')"
        if [ -z "$repo_line" ]; then
            echo "no remote repository associated with the current branch, exit 1"
            exit 1
        fi
    else
        repo_name="$(echo "$repo_name" | sed 's@/.*@@g')"

        repo_line="$(git remote -vv | grep "^${repo_name}[ ${TB}].*(fetch)\$")"
    fi

    if echo "$repo_line" | grep -q '[0-9a-z_-\.]\+@[a-z0-9_-\.]\+:'; then
        repo_id="$(echo "$repo_line" | sed "s/^[^ ${TB}]\+[ ${TB}]\+[^ ${TB}@]\+@//g;s/.git[ ${TB}]\+(fetch)$/.git/g;s@/${GEM_GIT_PACKAGE}.git@@g;s@:@/@g")"
    else
        repo_id="$(echo "$repo_line" | sed "s/^[^ ${TB}]\+[ ${TB}]\+git:\/\///g;s/.git[ ${TB}]\+(fetch)$/.git/g;s@/${GEM_GIT_PACKAGE}.git@@g")"
    fi

    echo "$repo_id"
}

#
#  mksafedir <dname> - try to create a directory and rise an alert if it already exists
#      <dname>    name of the directory to create
#
mksafedir () {
    local dname

    dname="$1"
    if [ "$GEM_ALWAYS_YES" != "true" -a -d "$dname" ]; then
        echo "$dname already exists"
        echo "press Enter to continue or CTRL+C to abort"
        read a
    fi
    rm -rf $dname
    mkdir -p $dname
}

#
#  usage <exitcode> - show usage of the script
#      <exitcode>    value of exitcode
#
usage () {
    local ret

    ret=$1

    echo
    echo "USAGE:"
    echo "    $0 devtest <branch-name>"
    echo "                                                 put oq-platform sources in a lxc,"
    echo "                                                 setup environment and run development tests."
    echo "    $0 prodtest <branch-name>"
    echo "                                                 production installation and tests."
    echo
    exit $ret
}

#
#  _wait_ssh <lxc_ip> - wait until the new lxc ssh daemon is ready
#      <lxc_ip>    the IP address of lxc instance
#
_wait_ssh () {
    local lxc_ip="$1"

    for i in $(seq 1 20); do
        if ssh $lxc_ip "echo begin"; then
            break
        fi
        sleep 2
    done
    if [ $i -eq 20 ]; then
        return 1
    fi
}

#
#  _devtest_innervm_run <branch_id> <lxc_ip> - part of source test performed on lxc
#                     the following activities are performed:
#                     - extracts dependencies from oq-{engine,hazardlib, ..} debian/control
#                       files and install them
#                     - builds oq-hazardlib speedups
#                     - installs oq-engine sources on lxc
#                     - set up postgres
#                     - upgrade db
#                     - runs celeryd
#                     - runs tests
#                     - runs coverage
#                     - collects all tests output files from lxc
#
#      <branch_id>    name of the tested branch
#      <lxc_ip>       the IP address of lxc instance
#
_devtest_innervm_run () {
    local i old_ifs pkgs_list dep branch_id="$1" lxc_ip="$2"

    trap 'local LASTERR="$?" ; trap ERR ; (exit $LASTERR) ; return' ERR

    scp .gem_init.sh ${lxc_ip}:
    scp .gem_ffox_init.sh ${lxc_ip}:

    # build oq-hazardlib speedups and put in the right place
    ssh -t  $lxc_ip "source .gem_init.sh"

    ssh -t  $lxc_ip "rm -f ssh.log"

    ssh -t  $lxc_ip "sudo apt-get update"
    ssh -t  $lxc_ip "sudo apt-get -y upgrade"

    ssh -t  $lxc_ip "sudo apt-get install -y build-essential python-dev python-imaging python-virtualenv git libxml2 libxml2-dev libxslt1-dev libxslt1.1 libblas-dev liblapack-dev curl wget xmlstarlet imagemagick gfortran python-nose libgeos-dev python-software-properties"
    ssh -t  $lxc_ip "sudo add-apt-repository -y ppa:openquake-automatic-team/latest-master"
    ssh -t  $lxc_ip "sudo apt-get update"
    ssh -t  $lxc_ip "sudo apt-get install -y python-decorator python-h5py python-psutil python-concurrent.futures python-oq-hazardlib python-oq-engine"

    repo_id="$GEM_GIT_REPO"
    ssh -t  $lxc_ip "git clone --depth=1 -b $branch_id $repo_id/$GEM_GIT_PACKAGE"
    ssh -t  $lxc_ip "git clone --depth=1 -b $branch_id $repo_id/oq-platform-ipt || git clone --depth=1 -b  $repo_id/oq-platform-ipt"
    ssh -t  $lxc_ip "git clone --depth=1 -b $branch_id $repo_id/oq-platform-taxtweb || git clone --depth=1 -b  $repo_id/oq-platform-taxtweb"
    ssh -t  $lxc_ip "export GEM_SET_DEBUG=$GEM_SET_DEBUG
rem_sig_hand() {
    trap ERR
    echo 'signal trapped'
    cd ~/$GEM_GIT_PACKAGE
    if [ -z \"\$VIRTUAL_ENV\" ]; then
        . platform-env/bin/activate
    fi
    cd openquakeplatform
    fab stop
}
trap rem_sig_hand ERR
set -e
if [ \$GEM_SET_DEBUG ]; then
    set -x
fi
cd ~/$GEM_GIT_PACKAGE
virtualenv --system-site-packages platform-env
source platform-env/bin/activate
# if host machine includes python-simplejson package it must overrided with
# a proper version that don't conflict with Django requirements
if dpkg -l python-simplejson 2>/dev/null | tail -n +6 | grep -q '^ii '; then
    pip install simplejson==2.0.9
fi
cd -
cd oq-platform-ipt
sudo python setup.py install
cd -
cd oq-platform-taxtweb
sudo python setup.py install
cd -
cd ~/$GEM_GIT_PACKAGE

pip install -e .

./runserver.sh &
server=$!
cp openquakeplatform_standalone/test/config.py.tmpl openquakeplatform_standalone/test/config.py
export DISPLAY=:1
python openquakeplatform_standalone/test/nose_runner.py --failurecatcher dev -v --with-xunit --xunit-file=xunit-platform-dev.xml  openquakeplatform_standalone/test
sleep 3
kill $server
sleep 3
if kill 0 $server ; then
    kill -KILL $server
fi
"

    echo "_devtest_innervm_run: exit"

    return 0
}


#
#  _lxc_name_and_ip_get <filename> - retrieve name and ip of the runned ephemeral lxc and
#                                    put them into global vars "lxc_name" and "lxc_ip"
#      <filename>    file where lxc-start-ephemeral output is saved
#
_lxc_name_and_ip_get()
{
    if [ "$GEM_EPHEM_IP_GET" = "" ]; then
        local filename="$1" i e

        i=-1
        e=-1
        for i in $(seq 1 40); do
            sleep 2
            if grep -q "sudo lxc-console -n $GEM_EPHEM_NAME" $filename 2>&1 ; then
                lxc_name="$(grep "sudo lxc-console -n $GEM_EPHEM_NAME" $filename | sed "s/.*sudo lxc-console -n \($GEM_EPHEM_NAME\)/\1/g")"
                for e in $(seq 1 40); do
                    sleep 2
                    if grep -q "$lxc_name" /var/lib/misc/dnsmasq*.leases ; then
                        lxc_ip="$(grep " $lxc_name " /var/lib/misc/dnsmasq*.leases | tail -n 1 | cut -d ' ' -f 3)"
                        break
                    fi
                done
                break
            fi
        done
        if [ $i -eq 40 -o $e -eq 40 ]; then
            return 1
        fi
        echo "SUCCESSFULY RUNNED $lxc_name ($lxc_ip)"

        return 0
    else
        lxc_ip="$(sudo $GEM_EPHEM_IP_GET "$GEM_EPHEM_NAME")"
        lxc_name="$GEM_EPHEM_NAME"
        if [ $? -ne 0 ]; then
            return 1
        fi
        echo "SUCCESSFULY RUNNED $lxc_name ($lxc_ip)"

        return 0
    fi
}

#
#  devtest_run <branch_id> - main function of source test
#      <branch_id>    name of the tested branch
#
devtest_run () {
    local deps old_ifs branch_id="$1"

    sudo echo
    sudo ${GEM_EPHEM_EXE} 2>&1 | tee /tmp/packager.eph.$$.log &
    _lxc_name_and_ip_get /tmp/packager.eph.$$.log
    rm /tmp/packager.eph.$$.log

    _wait_ssh $lxc_ip
    set +e
    _devtest_innervm_run "$branch_id" "$lxc_ip"
    inner_ret=$?

    copy_common dev
    copy_dev

    if [ $inner_ret != 0 ]; then
        ssh -t  $lxc_ip "cd ~/$GEM_GIT_PACKAGE; . platform-env/bin/activate ; killall runserver.sh"
    fi

    if [ "$LXC_DESTROY" = "lxc-destroy" ]; then
        sudo $LXC_TERM -n $lxc_name
    fi

    set -e

    return $inner_ret
}

#
#  _prodtest_innervm_run <branch_id> <lxc_ip> - part of source test performed on lxc
#                     the following activities are performed:
#                     - extracts dependencies from oq-{engine,hazardlib, ..} debian/control
#                       files and install them
#                     - builds oq-hazardlib speedups
#                     - installs oq-engine sources on lxc
#                     - set up postgres
#                     - upgrade db
#                     - runs celeryd
#                     - runs tests
#                     - runs coverage
#                     - collects all tests output files from lxc
#
#      <branch_id>    name of the tested branch
#      <lxc_ip>       the IP address of lxc instance
#
_prodtest_innervm_run () {
    local i old_ifs pkgs_list dep branch_id="$1" lxc_ip="$2"

    trap 'local LASTERR="$?" ; trap ERR ; (exit $LASTERR) ; return' ERR

    scp .gem_init.sh ${lxc_ip}:
    scp .gem_ffox_init.sh ${lxc_ip}:

    # build oq-hazardlib speedups and put in the right place
    ssh -t  $lxc_ip "source .gem_init.sh"

    ssh -t  $lxc_ip "getent hosts oq-platform.localdomain"
    ssh -t  $lxc_ip "rm -f ssh.log"

    ssh -t  $lxc_ip "sudo apt-get update"
    ssh -t  $lxc_ip "sudo apt-get -y upgrade"

    ssh -t  $lxc_ip "sudo apt-get install -y build-essential python-dev python-imaging python-virtualenv git postgresql-9.1 postgresql-server-dev-9.1 postgresql-9.1-postgis openjdk-6-jre libxml2 libxml2-dev libxslt1-dev libxslt1.1 libblas-dev liblapack-dev curl wget xmlstarlet imagemagick gfortran python-nose libgeos-dev python-software-properties"
    ssh -t  $lxc_ip "sudo add-apt-repository -y ppa:openquake-automatic-team/latest-master"
    ssh -t  $lxc_ip "sudo apt-get update"
    ssh -t  $lxc_ip "sudo apt-get install -y python-decorator python-h5py python-psutil python-concurrent.futures python-oq-hazardlib python-oq-engine"

    ssh -t  $lxc_ip "sudo sed -i '1 s@^@local   all             all                                     trust\nhost    all             all             $lxc_ip/32          md5\n@g' /etc/postgresql/9.1/main/pg_hba.conf"

    ssh -t  $lxc_ip "sudo sed -i \"s/\([#        ]*listen_addresses[     ]*=[    ]*\)[^#]*\(#.*\)*/listen_addresses = '*'    \2/g\" /etc/postgresql/9.1/main/postgresql.conf"

    ssh -t  $lxc_ip "sudo service postgresql restart"

    repo_id="$GEM_GIT_REPO"
    ssh -t  $lxc_ip "git clone --depth=1 -b $branch_id $repo_id/$GEM_GIT_PACKAGE"
    ssh -t  $lxc_ip "git clone --depth=1 -b $branch_id $repo_id/oq-platform-ipt || git clone --depth=1 -b  $repo_id/oq-platform-ipt"
    ssh -t  $lxc_ip "git clone --depth=1 -b $branch_id $repo_id/oq-platform-taxtweb || git clone --depth=1 -b  $repo_id/oq-platform-taxtweb"
    ssh -t  $lxc_ip "export GEM_SET_DEBUG=$GEM_SET_DEBUG
rem_sig_hand() {
    trap ERR
    echo 'signal trapped'
}
trap rem_sig_hand ERR
set -e
if [ \$GEM_SET_DEBUG ]; then
    set -x
fi

# install IPT
cd oq-platform-ipt
sudo pip install . -U --no-deps
cd -

# install taxtweb
cd oq-platform-taxtweb
sudo pip install . -U --no-deps
cd -

echo -e \"y\ny\ny\n\" | oq-platform/openquakeplatform/bin/deploy.sh --hostname oq-platform.localdomain

cd oq-platform/openquakeplatform

# add a simulated qgis uploaded layer
./openquakeplatform/bin/simqgis-layer-up.sh --sitename "http://oq-platform.localdomain"

export PYTHONPATH=\$(pwd)
sed 's@^pla_basepath *= *\"http://localhost:8000\"@pla_basepath = \"http://oq-platform.localdomain\"@g' openquakeplatform/test/config.py.tmpl > openquakeplatform/test/config.py
export DISPLAY=:1
python openquakeplatform/test/nose_runner.py --failurecatcher prod -v --with-xunit --xunit-file=xunit-platform-prod.xml  openquakeplatform/test
sleep 3
cd -
"
    echo "_prodtest_innervm_run: exit"

    return 0
}



#
#  devtest_run <branch_id> - main function of source test
#      <branch_id>    name of the tested branch
#
prodtest_run () {
    local deps old_ifs branch_id="$1"

    sudo echo
    sudo ${GEM_EPHEM_EXE} 2>&1 | tee /tmp/packager.eph.$$.log &
    _lxc_name_and_ip_get /tmp/packager.eph.$$.log
    rm /tmp/packager.eph.$$.log

    _wait_ssh $lxc_ip
    set +e
    _prodtest_innervm_run "$branch_id" "$lxc_ip"
    inner_ret=$?

    copy_common prod
    copy_prod

    if [ $inner_ret != 0 ]; then
        # cleanup in error case
        :
    fi

    if [ "$LXC_DESTROY" = "lxc-destroy" ]; then
        sudo $LXC_TERM -n $lxc_name
    fi

    set -e

    return $inner_ret
}


#
#  MAIN
#
BUILD_FLAGS=""

trap sig_hand SIGINT SIGTERM

# create folder to save logs
if [ ! -d "out" ]; then
    mkdir "out"
fi

#  args management
while [ $# -gt 0 ]; do
    case $1 in
        devtest)
            ACTION="$1"
            # Sed removes 'origin/' from the branch name
            devtest_run $(echo "$2" | sed 's@.*/@@g')
            exit $?
            break
            ;;
        prodtest)
            ACTION="$1"
            prodtest_run $(echo "$2" | sed 's@.*/@@g')
            break
            ;;
        *)
            usage 1
            break
            ;;
    esac
    BUILD_FLAGS="$BUILD_FLAGS $1"
    shift
done

exit 0