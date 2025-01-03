#!/bin/bash
#
# verifier.sh  Copyright (c) 2016, GEM Foundation.
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
# - create and run a new lxc of the same serie used here
#
# on the guest run:
# rm -rf oq-moon/ oq-platform-ipt/ oq-platform-standalone.old/ oq-platform-taxonomy/ oq-platform-taxtweb/ oqdata venv/ oq-engine/ selenium-deps*
#
# on the host run:
# export GEM_EPHEM_NAME='<lxc-machine-name>'
# export GEM_EPHEM_DESTROY='false'
# export GEM_EPHEM_EXE='<lxc-machine-name>'
#
# ./verifier.sh prodtest <your-branch-name>



# MAYBE GOOD FOR PRODUCTION TEST PART
# sudo apt-get install git
# git clone --depth 1 -b ci-test1 https://github.com/gem/oq-platform.git
# sudo sed -i  's/127.0.1.1   \+\([^ ]\+\)/127.0.1.1   \1 \1.gem.lan/g'  /etc/hosts
# # get name from hosts
# hname=...
# sed -i 's/127.0.1.1   \+\([^ ]\+\)/127.0.1.1   \1 \1.gem.lan/g'  /etc/hosts
# echo -e "y\ny\ny\n" | ./oq-platform/openquakeplatform/bin/deploy.sh -H $hname

# export PS4='+${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
if [ $GEM_SET_DEBUG ]; then
    set -x
fi
set -e
GEM_GIT_REPO="$(echo "${repository:-git@github.com:gem/oq-platform-standalone.git}" | sed 's@/[^/]*$@@g')"
GEM_GIT_PACKAGE="oq-platform-standalone"
GEM_DEB_PACKAGE="python-${GEM_GIT_PACKAGE}"
GEM_DEB_SERIE="master"
GEM_PYTHON_VERSION="python3.11"
GEM_PY_VERSION="py311"
if [ -z "$GEM_TOOLS_ONLY" ]; then
GEM_TOOLS_ONLY=${GEM_TOOLS_ONLY}
fi
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

if [ "$GEM_EPHEM_NAME" = "" ]; then
    GEM_EPHEM_NAME="ubuntu16-x11-lxc-eph"
fi

LXC_VER=$(lxc-ls --version | cut -d '.' -f 1)

if [ $LXC_VER -lt 2 ]; then
    echo "lxc >= 2.0.0 is required." >&2
    exit 1
fi

LXC_TERM="lxc-stop -t 10"
LXC_KILL="lxc-stop -k"

if [ "$GEM_EPHEM_EXE" != "" ]; then
    echo "Using [$GEM_EPHEM_EXE] to run lxc"
else
    GEM_EPHEM_EXE="lxc-copy -n ${GEM_EPHEM_NAME} -e"
fi

if [ "$GEM_EPHEM_DESTROY" != "" ]; then
    LXC_DESTROY="$GEM_EPHEM_DESTROY"
else
    LXC_DESTROY="true"
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
        # use this parameter to avoid blocks with sudoers updates: '-o Dpkg::Options::=--force-confdef'
        sudo apt-get -y upgrade
        sudo apt-get -y install wmctrl
        export DISPLAY=:1
        firefox &
        ffox_pid=\$!
        st="none"
        for i in \$(seq 1 1000) ; do
            if ! wmctrl -l >/dev/null; then
                sleep 0.1
                continue
            fi
            ffox_wins="\$(export DISPLAY=:1 ; wmctrl -l | grep -i "firefox" || true)"
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
    scp "${lxc_ip}:$GEM_GIT_PACKAGE/xunit-platform-dev_py3.xml" "out/" || true
    scp "${lxc_ip}:$GEM_GIT_PACKAGE/dev_*.png" "out/" || true
    scp "${lxc_ip}:example*.zip" "out/" || true
    scp "${lxc_ip}:runserver.log" "out/dev_runserver.log" || true
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

        copy_common "$ACTION"
        copy_dev
        copy_prod

        ssh -t $lxc_ip "
            if [ -f /tmp/server.pid ]; then
                server=\$(cat /tmp/server.pid)
                kill \$server
                sleep 3
                if kill -0 \$server >/dev/null 2>&1; then
                    kill -KILL \$server
                fi
            fi"

        echo "Destroying [$lxc_name] lxc"
        if [ "$LXC_DESTROY" = "true" ]; then
            sudo $LXC_KILL -n $lxc_name
        fi
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
    echo "    $0 devtest <branch-name> [<plugins-branch-name>]"
    echo "                                                 put oq-platform sources in a lxc,"
    echo "                                                 setup environment and run development tests."
    echo "    $0 prodtest <branch-name> [<plugins-branch-name>]"
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
#  _devtest_innervm_run <branch_id> <lxc_ip> <plugins_branch_id> - part of source test performed on lxc
#                     the following activities are performed:
#                     - update lxc packages
#                     - install ubuntu packaged dependencies
#                     - add openquake ppa with custom packages
#                     - install needed custom packages
#                     - copy the package on the LXC
#                     - clone package plugins
#                     - create and activate virtual environment
#                     - install package plugins
#                     - install package
#                     - run server
#                     - run tests
#                     - stop server
#                     - collects all tests output files from lxc
#
#      <branch_id>    name of the tested branch
#      <lxc_ip>       the IP address of lxc instance
#      <plugins_branch_id>  name of preferred branch for plugins
#
_devtest_innervm_run () {
    local i old_ifs pkgs_list dep branch_id="$1" lxc_ip="$2" plugins_branch_id="$3"
    local sa_apps
    trap 'local LASTERR="$?" ; trap ERR ; (exit $LASTERR) ; return' ERR

    scp .gem_init.sh ${lxc_ip}:
    scp .gem_ffox_init.sh ${lxc_ip}:

    sa_apps="$(python -c "from openquakeplatform.settings import STANDALONE_APPS ; print(' '.join(STANDALONE_APPS))")"
    # build oq-hazardlib speedups and put in the right place
    ssh -t  $lxc_ip "sudo systemctl stop apt-daily.timer"
    ssh -t  $lxc_ip "source .gem_init.sh"
    ssh -t  $lxc_ip "mkdir oqdata"

    ssh -t  $lxc_ip "rm -f ssh.log"

    ssh -t  $lxc_ip "sudo apt-get update"
    # use this parameter to avoid blocks with sudoers updates: '-o Dpkg::Options::=--force-confdef'
    ssh -t  $lxc_ip "sudo apt-get -y upgrade"

    repo_id="$GEM_GIT_REPO"
    # use copy of repository instead of clone it from github, if you want it comment next 2 lines and
    # uncomment the commented git clone line
    ssh -t  $lxc_ip "mkdir -p $GEM_GIT_PACKAGE"
    scp -r * "${lxc_ip}:$GEM_GIT_PACKAGE"
    sa_apps="oq-engine $sa_apps oq-moon"
    for app in $sa_apps; do
        app_repo="${app/openquakeplatform_/oq-platform-}"

        # ssh -t  $lxc_ip "git clone --depth=1 -b $branch_id $repo_id/$GEM_GIT_PACKAGE"
        if [ "$plugins_branch_id" ]; then
            plugins_pfx="git clone --depth=1 -b $plugins_branch_id $repo_id/$app_repo || "
        fi

        ssh -t  $lxc_ip "${plugins_pfx}git clone --depth=1 -b $branch_id $repo_id/${app_repo} || git clone --depth=1 $repo_id/${app_repo}"
    done
    ssh -t  $lxc_ip ":
export GEM_SET_DEBUG=$GEM_SET_DEBUG
export GEM_WAIT_BEFORE_CLOSE=$GEM_WAIT_BEFORE_CLOSE

install_with_reqs () {
    local app=\$1
    local app_reponame
    app_reponame=\"\${app/openquakeplatform_/oq-platform-}\"

    echo \"Python version:\"
    python --version
    if [ -f \${app_reponame}/requirements-${GEM_PY_VERSION}-${GEM_GIT_PACKAGE}-\${BUILD_OS}.txt ]; then
        sed 's/cdn\.ftp\.openquake\.org/ftp.openquake.org/g' \${app_reponame}/requirements-${GEM_PY_VERSION}-${GEM_GIT_PACKAGE}-\${BUILD_OS}.txt > \$REQMIRROR
        pip install -r \$REQMIRROR
    elif [ -f \${app_reponame}/requirements-${GEM_PY_VERSION}-\${BUILD_OS}.txt ]; then
        sed 's/cdn\.ftp\.openquake\.org/ftp.openquake.org/g' \${app_reponame}/requirements-${GEM_PY_VERSION}-\${BUILD_OS}.txt > \$REQMIRROR
        pip install -r \$REQMIRROR
    fi
    if [ \"\$app\" = \"oq-engine\" ]; then
        pip install -e \"\$app_reponame\"
    else
        pip install -e \"\$app_reponame\"
        if [ \"\$app_reponame\" = \"oq-platform-taxtweb\" ]; then
            export PYBUILD_NAME=oq-taxonomy
            pip install -e \"\$app_reponame\"
        fi
    fi
}

rem_sig_hand() {
    trap ERR
    echo 'signal trapped'
    if [ \"\$GEM_WAIT_BEFORE_CLOSE\" = \"true\" ]; then
         sleep 20000 || true
    fi
    if [ -f /tmp/server.pid ]; then
         server=\$(cat /tmp/server.pid)
         kill \$server
         sleep 3
         if kill -0 \$server >/dev/null 2>&1; then
             kill -KILL \$server
         fi
    fi
}
trap rem_sig_hand ERR
set -e
if [ \$GEM_SET_DEBUG ]; then
    set -x
fi

rm -f selenium-deps
wget \"http://ftp.openquake.org/common/selenium-deps-2023\"
GEM_FIREFOX_VERSION=\"\$(dpkg-query --show -f '\${Version}' firefox)\"
. selenium-deps-2023
wget \"http://ftp.openquake.org/mirror/mozilla/geckodriver-v\${GEM_GECKODRIVER_VERSION}-linux64.tar.gz\"
tar zxvf \"geckodriver-v\${GEM_GECKODRIVER_VERSION}-linux64.tar.gz\"
sudo cp geckodriver /usr/local/bin

cd \$HOME
#run it
eval '${GEM_PYTHON_VERSION} -c \"import sys; print(sys.version)\"'
sleep 2
eval '${GEM_PYTHON_VERSION} -m venv venv'
source venv/bin/activate
pip install -U pip
pip install -U nose3
pip install -U selenium==\${GEM_SELENIUM_VERSION}
pip install -e oq-moon/
REQMIRROR=\$(mktemp)
BUILD_OS=linux64

for app in oq-engine oq-platform-standalone; do
    install_with_reqs \"\$app\"
done
for app in \$(python -c 'from openquakeplatform.settings import STANDALONE_APPS ; print(\"\\n\".join(x for x in STANDALONE_APPS))'); do
    install_with_reqs \"\$app\"
done
rm -f \"\$REQMIRROR\"

rm -f demos-*.zip
wget https://artifacts.openquake.org/travis/demos-${plugins_branch_id}.zip || wget https://artifacts.openquake.org/travis/demos-master.zip
rm -rf demos
unzip demos-*.zip

# to avoid dates inside .ini files
export GEM_TIME_INVARIANT_OUTPUTS=y

# variable for numba to compile things
export NUMBA_DISABLE_JIT=1

# run webui
echo \$GEM_TOOLS_ONLY
echo \$TOOLS_DEV
sudo mkdir -p /var/www/webui
sudo chown -R ubuntu /var/www/webui
cd oq-engine/openquake/server
if [ -z \$GEM_TOOLS_ONLY ]; then
    cp local_settings.py.tools local_settings.py
fi
python manage.py migrate
python manage.py loaddata ./fixtures/0001_cookie_consent_required_plus_hide_cookie_bar.json
python manage.py loaddata ./fixtures/0002_cookie_consent_analytics.json
python manage.py collectstatic
cd \$HOME
export TOOLS_DEV=\"True\"
export EXTERNAL_TOOLS=\"True\"
oq webui start -s &> runserver.log &
server=\$!
echo \"\$server\" > /tmp/server.pid
# sleep 4000000

# FIXME Grace time for openquake.server to be started asynchronously
# should be replaced by a timeboxed loop with an availability check
sleep 10

cd $GEM_GIT_PACKAGE
cp openquakeplatform/test/config/moon_config.py.tmpl openquakeplatform/test/config/moon_config.py
export GEM_OPT_PACKAGES=\"\$(python -c 'from openquakeplatform.settings import STANDALONE_APPS ; print(\",\".join(x for x in STANDALONE_APPS))')\"
export PYTHONPATH=\$(pwd)/openquakeplatform/test/config
export DISPLAY=:1
engine_reply=0
for ti in \$(seq 1 50); do
    if curl --max-time 2 -s -o /dev/null -v http://127.0.0.1:8800/v1/ini_defaults ; then
        engine_reply=1
        break
    fi
    sleep 2
done
if [ \$engine_reply -ne 1 ]; then
    exit 1
fi
#sleep 40000
python -m openquake.moon.nose_runner --failurecatcher dev_py3 -v -s --with-xunit --xunit-file=xunit-platform-dev_py3.xml openquakeplatform/test # || true
sleep 3
#sleep 40000 || true
kill \$server
sleep 3
if kill -0 \$server >/dev/null 2>&1; then
    kill -KILL \$server
fi
deactivate
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
            if [ "$GEM_EPHEM_EXE" = "$GEM_EPHEM_NAME" ]; then
                lxc_name="$GEM_EPHEM_NAME"
                break
            elif grep -q " as clone of $GEM_EPHEM_NAME" $filename 2>&1 ; then
                lxc_name="$(grep " as clone of $GEM_EPHEM_NAME" $filename | tail -n 1 | sed "s/Created \(.*\) as clone of ${GEM_EPHEM_NAME}/\1/g")"
                break
            else
                sleep 2
            fi
        done
        if [ $i -eq 40 ]; then
            return 1
        fi

        for e in $(seq 1 40); do
            sleep 2
            lxc_ip="$(sudo lxc-ls -f --filter "^${lxc_name}\$" | tail -n 1 | sed 's/ \+/ /g' | cut -d ' ' -f 5)"
            if [ "$lxc_ip" -a "$lxc_ip" != "-" ]; then
                break
            fi
        done
        if [ $e -eq 40 ]; then
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
    local deps old_ifs branch_id="$1" plugins_branch_id="$2"

    if [ "$branch_id" = "$plugins_branch_id" ]; then
        plugins_branch_id=""
    fi

    sudo echo
    if [ "$GEM_EPHEM_EXE" = "$GEM_EPHEM_NAME" ]; then
        _lxc_name_and_ip_get
    else
        sudo ${GEM_EPHEM_EXE} 2>&1 | tee /tmp/packager.eph.$$.log &
        _lxc_name_and_ip_get /tmp/packager.eph.$$.log
        rm /tmp/packager.eph.$$.log
    fi

    _wait_ssh $lxc_ip
    set +e
    _devtest_innervm_run "$branch_id" "$lxc_ip" "$plugins_branch_id"
    inner_ret=$?

    copy_common dev
    copy_dev

    if [ $inner_ret != 0 ]; then
        ssh -t  $lxc_ip "cd ~/$GEM_GIT_PACKAGE; . platform-env/bin/activate ; killall runserver.sh"
    fi

    if [ "$LXC_DESTROY" = "true" ]; then
        sudo $LXC_TERM -n $lxc_name
    fi

    set -e

    return $inner_ret
}

#
#  _prodtest_innervm_run <branch_id> <lxc_ip> - part of source test performed on lxc
#
#      <branch_id>    name of the tested branch
#      <lxc_ip>       the IP address of lxc instance
#
_prodtest_innervm_run () {
    local i old_ifs pkgs_list dep branch_id="$1" lxc_ip="$2"

    trap 'local LASTERR="$?" ; trap ERR ; (exit $LASTERR) ; return' ERR

    # To be implemented

    return 0
}



#
#  prodtest_run <branch_id> - main function of source test
#      <branch_id>    name of the tested branch
#
prodtest_run () {
    local deps old_ifs branch_id="$1"

    sudo echo
    if [ "$GEM_EPHEM_EXE" = "$GEM_EPHEM_NAME" ]; then
        _lxc_name_and_ip_get
    else
        sudo ${GEM_EPHEM_EXE} 2>&1 | tee /tmp/packager.eph.$$.log &
        _lxc_name_and_ip_get /tmp/packager.eph.$$.log
        rm /tmp/packager.eph.$$.log
    fi

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

    if [ "$LXC_DESTROY" = "true" ]; then
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
            devtest_run $(echo "$2" | sed 's@.*/@@g') "$3"
            exit $?
            break
            ;;
        prodtest)
            ACTION="$1"
            # prodtest_run $(echo "$2" | sed 's@.*/@@g') "$3"
            echo "prodtest not yet implemented"
            exit 1
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
