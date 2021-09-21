#! /bin/sh
#
# build script with dockcross
#

dash_version="0.5.11.5"
dash_sha1="ac1d533ec4eaae94936cb57dbf8f4c68ec3c4bfa"
musl_version="1.2.2"
musl_sha1="e7ba5f0a5f89c13843b955e916f1d9a9d4b6ab9a"

release_dir="dash-static-${dash_version}_musl-${musl_version}"

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
LDFLAGS=
musl_configure=
dash_configure=
strip=
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
	LDFLAGS="-m32"
	strip=strip
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
download "http://gondor.apana.org.au/~herbert/dash/files/dash-${dash_version}.tar.gz" $dash_sha1

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
./dockcross bash -c "cd '${dash_dir}' && [ -x autogen.sh ] && ./autogen.sh"
./dockcross bash -c "cd '${dash_dir}' && ./configure 'CC=$CC -static $CFLAGS' 'CPP=$CC -static $CFLAGS -E' 'LDFLAGS=$LDFLAGS' --enable-static ${dash_configure} --host=x86_64-unknown-linux-gnu"
./dockcross bash -c "cd '${dash_dir}' && make"

cd "${curdir}"

[ -d "${release_dir}" ] || mkdir -p "${release_dir}"

echo "= copy dash binary"
cp "${build_dir}/dash-${dash_version}/src/dash.1" "${release_dir}"
cp "${build_dir}/dash-${dash_version}/src/dash"   "${release_dir}/dash-${arch}"
if [ x"$strip" = x"" ]; then
    "${build_dir}/dockcross" bash -c 'STRIP=$(echo $CC|sed s/-gcc\$/-strip/); $STRIP -s '"'${release_dir}/dash-${arch}'"
else
    "${build_dir}/dockcross" bash -c "$strip -s '${release_dir}/dash-${arch}'"
fi

# remove ACL at macOS
uname_s=$(uname -s)
if [ x"$uname_s" = x"Darwin" ]; then
    xattr -d com.docker.owner "${release_dir}/dash-${arch}"
fi

echo "= done"
