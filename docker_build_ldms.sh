#!/bin/bash
# This is a simple automation that will write and utilize a Dockerfile
# to pull a debian image, and within it build from source tag v4.4.3 OVIS-HPC/ovis.git
# for the target platform arch (i.e., ARM64), then extract from the image a 
# archive that is able to be extracted onto a HPE Slingshot Switch
# usage: ./run_ldms_docker.sh

heredoc_dockerfile () {
cat << DOCKERFILE >Dockerfile
FROM docker.io/ubuntu:noble

RUN apt update \\
    && apt install -y \\
       autoconf \\
       bash \\
       bison \\
       build-essential \\
       flex \\
       less \\
       libssl-dev \\
       libtool \\
       make \\
       papi \\
       papi-devel \\
       libpfm \\
       libpfm-devel \\
       git \\
       pkg-config
RUN sh <<EOF > /build.log
git clone http://github.com/ovis-hpc/ovis.git -b v4.4.4 && \\
cd ovis && \\
[ -x autogen.sh ] && ./autogen.sh &&
[ -x configure ] &&
./configure \\
  CC=/usr/bin/gcc CXX=/usr/bin/g++ \
  --prefix=${LDMS_PREFIX} \\
  --libdir=${LDMS_PREFIX}/lib64 \\
  --enable-appinfo \
  --enable-app-sampler \
  --enable-test_sampler \
  --enable-rdma \
  --enable-munge \
  --enable-ssl \
  --enable-ovis_event_test \
  --enable-developer \
  --enable-doc \
  --enable-python \
  --enable-papi \
  --with-slurm=no \
  --with-libpapi-prefix=/usr/ \
  --with-libpfm-prefix=/usr/ \
  --disable-hello_stream \
  CFLAGS="-g -O0 -fPIC" \
  PYTHON_VERSION="3.6"
  make -j && make install && cd ../ &&
EOF
DOCKERFILE
}
#REGISTRY_URL="https://index.docker.io/v1/"
read -s -p "Enter Docker Hub Username: " DOCKER_USERNAME
echo ""
read -s -p "Enter Docker Hub Password: " DOCKER_PASSWORD
echo ""
echo "$DOCKER_PASSWORD" | docker login -u ${DOCKER_USERNAME} --password-stdin 
#echo "$DOCKER_PASSWORD" | docker login $REGISTRY_URL -u ${DOCKER_USERNAME} --password-stdin 
unset DOCKER_PASSWORD

# Setup the Dockerfile via a heredoc function (adjustable above ^^)
LDMS_PREFIX="/ovis_v4.4.4"
[ -f Dockerfile ] && rm Dockerfile
heredoc_dockerfile
docker build -t ldms-slingshot-build .

# Establish a staging area for the archive, then a "tar" entrypoint to redirect there
LDMS_ARTIFACT_PATH="${PWD}/archives"
[ -f ${LDMS_ARTIFACT_PATH}/${LDMS_PREFIX//\/}.tar.xz ] && \
  mv ${LDMS_ARTIFACT_PATH}/${LDMS_PREFIX//\/}.tar.xz \
  ${LDMS_ARTIFACT_PATH}/${LDMS_PREFIX//\/}.tar.xz.$(date +%m-%d-%y"-"%H.%M.%S)
mkdir -p $LDMS_ARTIFACT_PATH

docker run --entrypoint tar ldms-slingshot-build \
                        cjf - ${LDMS_PREFIX} \
                        > ${LDMS_ARTIFACT_PATH}/${LDMS_PREFIX//\/}.tar.xz

# Sanity Check the created archive

[ -f ${LDMS_ARTIFACT_PATH}/${LDMS_PREFIX//\/}.tar.xz ] && \
  echo "LDMS Ubuntu Installation for ARM64 Slingshot Switch Samplers \
  is at $(readlink -f ${LDMS_ARTIFACT_PATH}/${LDMS_PREFIX//\/}.tar.xz)" ||
  echo "Archive at ${LDMS_ARTIFACT_PATH}/${LDMS_PREFIX//\/}.tar.xz not found!"
# Sanity Check the sampler libs and script staging in archive
tar --extract --file=${LDMS_ARTIFACT_PATH}/${LDMS_PREFIX//\/}.tar.xz \
  ${LDMS_PREFIX//\/}/bin/gen_switch_config.sh \
  && file ${LDMS_PREFIX//\/}/bin/gen_switch_config.sh \
  && rm -Rf ${LDMS_PREFIX//\/}
tar --extract --file=${LDMS_ARTIFACT_PATH}/${LDMS_PREFIX//\/}.tar.xz \
  ${LDMS_PREFIX//\/}/lib64/ovis-ldms/libslingshot_switch.so.0.0.0 \
  && file ${LDMS_PREFIX//\/}/lib64/ovis-ldms/libslingshot_switch.so.0.0.0 \
  && rm -Rf ${LDMS_PREFIX//\/}
