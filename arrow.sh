package: arrow
version: v0.17.0
tag: apache-arrow-0.17.0
source: https://github.com/apache/arrow
requires:
  - boost
  - lz4
  - Clang
  - protobuf
build_requires:
  - zlib
  - flatbuffers
  - RapidJSON
  - CMake
  - double-conversion
  - re2
env:
  ARROW_HOME: "$ARROW_ROOT"
---

mkdir -p $INSTALLROOT
case $ARCHITECTURE in
  osx*)
    # If we preferred system tools, we need to make sure we can pick them up.
    [[ ! $FLATBUFFERS_ROOT ]] && FLATBUFFERS_ROOT=$(dirname $(dirname $(which flatc)))
    [[ ! $BOOST_ROOT ]] && BOOST_ROOT=$(brew --prefix boost)
    [[ ! $LZ4_ROOT ]] && LZ4_ROOT=$(dirname $(dirname $(which lz4)))
    [[ ! $PROTOBUF_ROOT ]] && PROTOBUF_ROOT=$(dirname $(dirname $(which protoc)))
    [[ ! -d $FLATBUFFERS_ROOT ]] && unset FLATBUFFERS_ROOT
    [[ ! -d $BOOST_ROOT ]] && unset BOOST_ROOT
    [[ ! -d $LZ4_ROOT ]] && unset LZ4_ROOT
    [[ ! -d $PROTOBUF_ROOT ]] && unset PROTOBUF_ROOT
    MACOSX_RPATH=OFF
    SONAME=dylib
    cat >no-llvm-symbols.txt << EOF
_LLVM*
__ZN4llvm*
__ZNK4llvm*
EOF
    CMAKE_SHARED_LINKER_FLAGS="-Wl,-unexported_symbols_list,$PWD/no-llvm-symbols.txt"
  ;;
  *) SONAME=so ;;
esac

# Downloaded by CMake, built, and linked statically (not needed at runtime):
#   zlib, lz4, brotli
#
# Taken from our stack, linked statically (not needed at runtime):
#   flatbuffers
#
# Taken from our stack, linked dynamically (needed at runtime):
#   boost

mkdir -p ./src_tmp
rsync -a --exclude='**/.git' --delete --delete-excluded "$SOURCEDIR/" ./src_tmp/
CLANG_VERSION_SHORT=`echo $CLANG_VERSION | sed "s/\.[0-9]*\$//" | sed "s/^v//"`
sed -i.deleteme -e "s/set(ARROW_LLVM_VERSION \".*\")/set(ARROW_LLVM_VERSION \"$CLANG_VERSION_SHORT\")/" "./src_tmp/cpp/CMakeLists.txt" || true
sed -i.deleteme -e "s/set(ARROW_LLVM_VERSIONS \".*\")/set(ARROW_LLVM_VERSIONS \"$CLANG_VERSION_SHORT\")/" "./src_tmp/cpp/CMakeLists.txt" || true

case $ARCHITECTURE in
  osx*) ;;
  *)
   # this patches version script to hide llvm symbols in gandiva library
   sed -i.deleteme '/^[[:space:]]*extern/ a \ \ \ \ \ \ llvm*; LLVM*;' "./src_tmp/cpp/src/gandiva/symbols.map"
   ;;
esac

cmake ./src_tmp/cpp                                                                                 \
      ${CMAKE_SHARED_LINKER_FLAGS:+-DCMAKE_SHARED_LINKER_FLAGS=${CMAKE_SHARED_LINKER_FLAGS}}        \
      -DARROW_DEPENDENCY_SOURCE=SYSTEM                                                              \
      -DCMAKE_BUILD_TYPE=Release                                                                    \
      -DCMAKE_CXX_STANDARD=17                                                                       \
      -DBUILD_SHARED_LIBS=TRUE                                                                      \
      -DARROW_BUILD_BENCHMARKS=OFF                                                                  \
      -DARROW_BUILD_TESTS=OFF                                                                       \
      -DARROW_USE_GLOG=OFF                                                                          \
      -DARROW_JEMALLOC=OFF                                                                          \
      -DARROW_HDFS=OFF                                                                              \
      -DARROW_IPC=ON                                                                                \
      ${THRIFT_ROOT:+-DARROW_PARQUET=ON}                                                            \
      ${THRIFT_ROOT:+-DThrift_ROOT=${THRIFT_ROOT}}                                                  \
      ${FLATBUFFERS_ROOT:+-DFlatbuffers_ROOT=${FLATBUFFERS_ROOT}}                                   \
      -DCMAKE_INSTALL_LIBDIR="lib"                                                                  \
      -DARROW_WITH_LZ4=ON                                                                           \
      ${RAPIDJSON_ROOT:+-DRapidJSON_ROOT=${RAPIDJSON_ROOT}}                                         \
      ${PROTOBUF_ROOT:+-DProtobuf_LIBRARY=$PROTOBUF_ROOT/lib/libprotobuf.$SONAME}                   \
      ${PROTOBUF_ROOT:+-DProtobuf_LITE_LIBRARY=$PROTOBUF_ROOT/lib/libprotobuf-lite.$SONAME}         \
      ${PROTOBUF_ROOT:+-DProtobuf_PROTOC_LIBRARY=$PROTOBUF_ROOT/lib/libprotoc.$SONAME}              \
      ${PROTOBUF_ROOT:+-DProtobuf_INCLUDE_DIR=$PROTOBUF_ROOT/include}                               \
      ${PROTOBUF_ROOT:+-DProtobuf_PROTOC_EXECUTABLE=$PROTOBUF_ROOT/bin/protoc}                      \
      ${BOOST_ROOT:+-DBoost_ROOT=$BOOST_ROOT}                                                       \
      ${LZ4_ROOT:+-DLZ4_ROOT=${LZ4_ROOT}}                                                           \
      -DARROW_WITH_SNAPPY=OFF                                                                       \
      -DARROW_WITH_ZSTD=OFF                                                                         \
      -DARROW_WITH_BROTLI=OFF                                                                       \
      -DARROW_WITH_ZLIB=ON                                                                          \
      -DARROW_NO_DEPRECATED_API=ON                                                                  \
      -DCMAKE_INSTALL_PREFIX=$INSTALLROOT                                                           \
      -DARROW_PYTHON=OFF                                                                            \
      -DARROW_TENSORFLOW=ON                                                                         \
      -DARROW_GANDIVA=ON                                                                            \
      -DARROW_COMPUTE=ON                                                                            \
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON                                                        \
      -DARROW_LLVM_VERSIONS=9                                                                       \
      -DCLANG_EXECUTABLE=${CLANG_ROOT}/bin-safe/clang

make ${JOBS:+-j $JOBS}
make install

# Modulefile
MODULEDIR="$INSTALLROOT/etc/modulefiles"
MODULEFILE="$MODULEDIR/$PKGNAME"
mkdir -p "$MODULEDIR"
cat > "$MODULEFILE" <<EoF
#%Module1.0
proc ModulesHelp { } {
  global version
  puts stderr "ALICE Modulefile for $PKGNAME $PKGVERSION-@@PKGREVISION@$PKGHASH@@"
}
set version $PKGVERSION-@@PKGREVISION@$PKGHASH@@
module-whatis "ALICE Modulefile for $PKGNAME $PKGVERSION-@@PKGREVISION@$PKGHASH@@"
# Dependencies
module load BASE/1.0 ${BOOST_REVISION:+boost/$BOOST_VERSION-$BOOST_REVISION} \\
                     ${CLANG_REVISION:+Clang/$CLANG_VERSION-$CLANG_REVISION}
# Our environment
set ARROW_ROOT \$::env(BASEDIR)/$PKGNAME/\$version
prepend-path LD_LIBRARY_PATH \$ARROW_ROOT/lib
EoF
