#! /bin/sh
#
# build static bash because we need exercises in minimalism
# MIT licensed: google it or see robxu9.mit-license.org.
#
# For Linux, also builds musl for truly static linking.

dash_version="0.5.10.2"
dash_sha1="cd1e4df124b989ae64a315bdcb40fb52b281504c"
musl_version="1.1.23"
musl_sha1="98f3991d67e0e11dd091eb65890285d8417c7d05"

if [ -z "$1" ]; then
    echo "Usage: $0 ARCH"
    echo ""
    echo "   supported ARCHes are"
    echo "     arm64, armhf, armel, i486, amd64, mips, mipsel,"
    echo "     powerpc, ppc64el, s390x"
    echo ""
    exit 1
fi

CFLAGS=
musl_configure=
dash_configure=
arch="$1"
case $arch in
    arm64)
	dockcross_arch=linux-arm64
	;;
    armhf)
	dockcross_arch=linux-armv7
	CFLAGS="-mfloat-abi=hard"
	;;
    armel)
	dockcross_arch=linux-armv5
    	CFLAGS="-mfloat-abi=soft"
    	;;
    i486) #broken
	dockcross_arch=linux-x86
	musl_configure="--target i386-linux-gnu RANLIB=ranlib"
	dash_configure="--target i386-unknown-linux-gnu"
	CFLAGS="-march=i486 -m32"
	;;
    amd64)
	dockcross_arch=linux-x64
	;;
    mips) 
	dockcross_arch=linux-mips
	;;
    mipsel)
	dockcross_arch=linux-mipsel
	;;
    powerpc) #broken
	dockcross_arch=linux-ppc64le
	musl_configure="--target powerpc-linux-gnu"
	dash_configure="--target powerpc-uknown-linux-gnu"
	CFLAGS="-m32 -mbig -mlong-double-64"
	;;
    ppc64el)
	dockcross_arch=linux-ppc64le
	CFLAGS="-mlong-double-64"
	;;
    s390x)
	dockcross_arch=linux-s390x
	;;
    *)
	echo "unknown archtecture $arch"
	exit 1
	;;
esac

build_dir="$(pwd)/build"
archives_dir="$(pwd)/archives"

sha1_digest() {
    FILE="$1"
    shasum=
    for bindir in /usr/bin /usr/local/bin /usr/pkg/bin /opt/local/bin; do
	if [ -x "${bindir}/shasum" ]; then
	    shasum="${bindir}/shasum"
	    break
	fi
    done
    if [ x"$shasum" = x"" ]; then
	shasum='openssl dgst -sha1 -r'
    fi
    $shasum "$FILE" | awk '{print $1}'
}

download() {
    URL="$1"
    SHA="$2"
    [ -d "$archives_dir" ] || mkdir -p "$archives_dir"
    filename="$(basename "$URL")"
    if [ -r "${archives_dir}/${filename}" ]; then
	digest=$(sha1_digest "${archives_dir}/${filename}")
	if [ x"$digest" = x"$SHA" ]; then
	    return
	fi
	rm -f "${archives_dir}/${filename}"
    fi
    curl -L -o "${archives_dir}/${filename}" "${URL}"
}


if [ -d "$build_dir" ]; then
  echo "= removing previous build directory"
  rm -rf "$build_dir"
fi

mkdir -p "$build_dir"
curdir="$(pwd)"
cd "$build_dir"
working_dir="$(pwd)"

docker run --rm "dockcross/${dockcross_arch}" > ./dockcross
chmod +x dockcross
./dockcross update # update dockcross environment!
dockerwork_dir=$(./dockcross bash -c 'echo -n $(pwd)')

# download tarballs
echo "= downloading dash"
download "https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-${dash_version}.tar.gz" $dash_sha1

echo "= extracting dash"
tar xf "${archives_dir}/dash-${dash_version}.tar.gz"

echo "= downloading musl"
download "http://www.musl-libc.org/releases/musl-${musl_version}.tar.gz" $musl_sha1

echo "= extracting musl"
tar xf "${archives_dir}/musl-${musl_version}.tar.gz"

echo "= building musl"

install_dir="${dockerwork_dir}/musl-install"
musl_dir="musl-${musl_version}"
./dockcross bash -c "cd ${musl_dir} && ./configure '--prefix=${install_dir}' --disable-shared ${musl_configure} 'CFLAGS=$CFLAGS'"
./dockcross bash -c "cd ${musl_dir} && make install"

echo "= setting CC to musl-gcc"
CC="${dockerwork_dir}/musl-install/bin/musl-gcc"

echo "= building dash"

dash_dir="dash-${dash_version}"
./dockcross bash -c "cd '${dash_dir}' && ./autogen.sh"
./dockcross bash -c "cd '${dash_dir}' && ./configure 'CC=$CC -static $CFLAGS' 'CPP=$CC -static $CFLAGS -E' --enable-static ${dash_configure} --host=x86_64-unknown-linux-gnu"
./dockcross bash -c "cd '${dash_dir}' && make"

cd "${curdir}"

[ -d releases ] || mkdir releases

echo "= copy dash binary"
cp ${build_dir}/dash-${dash_version}/src/dash.1 releases
cp ${build_dir}/dash-${dash_version}/src/dash   "releases/dash-${arch}"
${build_dir}/dockcross bash -c 'STRIP=$(echo $CC|sed s/-gcc\$/-strip/); $STRIP -s 'releases/dash-${arch}

echo "= done"
