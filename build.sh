#! /bin/sh
#
# build script with dockcross
#

dash_version="0.5.12"
dash_sha1="e15444a93853f693774df003f87d9040ab600a5e"
musl_version="1.2.5"
musl_sha1="36210d3423172a40ddcf83c762207c5f760b60a6"
musl_patch1="https://www.openwall.com/lists/musl/2025/02/13/1/1"
musl_patch1_sha1="83b881fbe8a5d4d340977723adda4f8ac66592f0"
musl_patch2="https://www.openwall.com/lists/musl/2025/02/13/1/2"
musl_patch2_sha1="0ceaa0467429057efce879b6346efa4f58c7cd4d"

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
link_hack=
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
    i486)
	#dockcross_arch=linux-x86
	dockcross_arch=linux-i686
	musl_configure="--target i386-linux-gnu RANLIB=ranlib"
	dash_configure="--target i386-unknown-linux-gnu"
	CFLAGS="-march=i486 -m32"
	LDFLAGS="-m32"
	link_hack=-melf_i386
	strip=strip
	;;
    amd64)
	dockcross_arch=linux-x64
	;;
    mips) 
	dockcross_arch=linux-mips
	;;
    mipsel)
	dockcross_arch=linux-mipsel-lts
	;;
    powerpc)
	dockcross_arch=linux-ppc
	CFLAGS="-mbig -mlong-double-64"
	;;
    ppc64el)
	dockcross_arch=linux-ppc64le
	CFLAGS="-mlong-double-64"
	;;
    riscv32)
	dockcross_arch=linux-riscv32
	;;
    riscv64)
	dockcross_arch=linux-riscv64
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
    filename="$3"
    [ -d "$archives_dir" ] || mkdir -p "$archives_dir"
    if [ x"$filename" = x"" ]; then
	filename="$(basename "$URL")"
    fi
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
gzip -dc "${archives_dir}/dash-${dash_version}.tar.gz" | tar xf -

echo "= downloading musl"
download "http://www.musl-libc.org/releases/musl-${musl_version}.tar.gz" $musl_sha1
download $musl_patch1 $musl_patch1_sha1 musl.patch1
download $musl_patch2 $musl_patch2_sha1 musl.patch2

echo "= extracting musl"
musl_dir="musl-${musl_version}"
gzip -dc "${archives_dir}/musl-${musl_version}.tar.gz" | tar xf -
(cd ${musl_dir} && patch -p1 < "${archives_dir}/musl.patch1")
(cd ${musl_dir} && patch -p1 < "${archives_dir}/musl.patch2")

echo "= building musl"

install_dir="${dockerwork_dir}/musl-install"
./dockcross bash -c "cd ${musl_dir} && ./configure '--prefix=${install_dir}' --disable-shared ${musl_configure} 'CFLAGS=$CFLAGS'"
./dockcross bash -c "cd ${musl_dir} && make install"

echo "= setting CC to musl-gcc"
CC="${dockerwork_dir}/musl-install/bin/musl-gcc"
if [ ! -z "$link_hack" ]; then
    echo "= hack for link with musl-gcc"
    sed -i.bak "s/-dynamic-linker/$link_hack -dynamic-linker/" "${working_dir}/musl-install/lib/musl-gcc.specs"
fi

echo "= building dash"

dash_dir="dash-${dash_version}"
./dockcross bash -c "cd '${dash_dir}' && [ -x autogen.sh ] && ./autogen.sh"
./dockcross bash -c "cd '${dash_dir}' && ./configure 'CC=$CC -static $CFLAGS' 'CPP=$CC -static $CFLAGS -E' 'LDFLAGS=$LDFLAGS' --enable-static ${dash_configure} --host=x86_64-unknown-linux-gnu"
./dockcross bash -c "cd '${dash_dir}' && make"

cd "${curdir}"

[ -d "${release_dir}" ] || mkdir -p "${release_dir}"

echo "= copy dash binary"
cp "${build_dir}/dash-${dash_version}/COPYING"    "${release_dir}"
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
    for a in com.docker.owner com.docker.grpcfuse.ownership; do
        xattr -d "$a" "${release_dir}/dash-${arch}" >/dev/null 2>&1
    done
fi

echo "= done"
