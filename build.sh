#! /bin/sh
#
# build static bash because we need exercises in minimalism
# MIT licensed: google it or see robxu9.mit-license.org.
#
# For Linux, also builds musl for truly static linking.

dash_version="0.5.10.2"
musl_version="1.1.23"

arch=linux-arm64

if [ -d build ]; then
  echo "= removing previous build directory"
  rm -rf build
fi

mkdir build # make build directory
curdir="$(pwd)"
cd build
working_dir="$(pwd)"

docker run --rm dockcross/$arch > ./dockcross
chmod +x dockcross
dockerwork_dir=$(./dockcross bash -c 'echo -n $(pwd)')

# download tarballs
echo "= downloading dash"
curl -LO "https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-${dash_version}.tar.gz"

echo "= extracting dash"
tar -xf dash-${dash_version}.tar.gz

echo "= downloading musl"
curl -LO http://www.musl-libc.org/releases/musl-${musl_version}.tar.gz

echo "= extracting musl"
tar -xf musl-${musl_version}.tar.gz

echo "= building musl"

install_dir="${dockerwork_dir}/musl-install"
musl_dir="musl-${musl_version}"
./dockcross bash -c "cd ${musl_dir} && ./configure '--prefix=${install_dir}'"
./dockcross bash -c "cd ${musl_dir} && make install"

echo "= setting CC to musl-gcc"
CC="${dockerwork_dir}/musl-install/bin/musl-gcc"
CFLAGS=

echo "= building dash"

dash_dir="dash-${dash_version}"
./dockcross bash -c "cd '${dash_dir}' && ./autogen.sh"
./dockcross bash -c "cd '${dash_dir}' && ./configure 'CC=$CC' CFLAGS='$CFLAGS -Os' --enable-static --host=x86_64-unknown-linux-gnu"
./dockcross bash -c "cd '${dash_dir}' && make"

cd "${curdir}"

if [ ! -d releases ]; then
  mkdir releases
fi

echo "= extracting dash binary"
cp build/dash-${dash_version}/src/dash.1 releases
cp build/dash-${dash_version}/src/dash   releases
build/dockcross bash -c 'STRIP=$(echo $CC|sed s/-gcc\$/-strip/); $STRIP releases/dash'

echo "= done"
