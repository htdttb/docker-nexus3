# Copyright (c) 2016-present Haluk Tutuk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM       centos:centos7

MAINTAINER Haluk Tutuk <Haluk.Tutuk@dataturbine.co.uk>

LABEL vendor=Sonatype \
  com.sonatype.license="Apache License, Version 2.0" \
  com.sonatype.name="Nexus Repository Manager base image"

RUN yum install -y \
  curl tar \
  && yum clean all

ARG JAVA_VERSION_MAJOR=8
ARG JAVA_VERSION_MINOR=121 
ARG JAVA_VERSION_BUILD=13
ARG NEXUS_VERSION=3.2.1-01

ARG JAVA_DOWNLOAD_URL=http://download.oracle.com/otn-pub/java/jdk/${JAVA_VERSION_MAJOR}u${JAVA_VERSION_MINOR}-b${JAVA_VERSION_BUILD}/e9e7ea248e2c4826b92b3f075a80e441/server-jre-${JAVA_VERSION_MAJOR}u${JAVA_VERSION_MINOR}-linux-x64.tar.gz 
ARG NEXUS_DOWNLOAD_URL=https://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-unix.tar.gz

# configure java runtime
ENV JAVA_HOME=/opt/java

# configure nexus runtime
ENV SONATYPE_DIR=/opt/sonatype
ENV NEXUS_HOME=${SONATYPE_DIR}/nexus \
    NEXUS_DATA=/nexus-data \
    NEXUS_CONTEXT='' \
    SONATYPE_WORK=${SONATYPE_DIR}/sonatype-work

# configure ssl - https runtime
ENV NEXUS_KEYSTORE ${NEXUS_DATA}/etc/ssl

ARG KEYSTOREPASSWORD=changeit
ARG KEYMANAGERPASSWORD=changeit
ARG TRUSTSTOREPASSWORD=changeit

CMD echo ${JAVA_DOWNLOAD_URL}

# install Oracle JRE
RUN mkdir -p /opt && cd /opt \
  && curl --fail --silent --location --header "Cookie: oraclelicense=accept-securebackup-cookie; " \
    ${JAVA_DOWNLOAD_URL} \
  | tar zxf - \
  && ln -s /opt/jdk1.${JAVA_VERSION_MAJOR}.0_${JAVA_VERSION_MINOR} ${JAVA_HOME}

# install nexus
RUN mkdir -p ${NEXUS_HOME} \
  && curl --fail --silent --location \
    ${NEXUS_DOWNLOAD_URL} \
  | gunzip \
  | tar x -C ${NEXUS_HOME} --strip-components=1 nexus-${NEXUS_VERSION} \
  && chown -R root:root ${NEXUS_HOME}

# configure nexus
RUN sed \
    -e '/^nexus-context/ s:$:${NEXUS_CONTEXT}:' \
    -e '/^application-port/s:$:\napplication-port-ssl=8443:' \
    -e '/^nexus-args/s:$:,${jetty.etc}/jetty-https.xml:' \
  -i ${NEXUS_HOME}/etc/nexus-default.properties

RUN useradd -r -u 200 -m -c "nexus role account" -d ${NEXUS_DATA} -s /bin/false nexus \
 && mkdir -p ${NEXUS_DATA}/etc ${NEXUS_DATA}/etc/ssl ${NEXUS_DATA}/log ${NEXUS_DATA}/tmp ${SONATYPE_WORK} \
 && ln -s ${NEXUS_DATA} ${SONATYPE_WORK}/nexus3 \
 && rm -rf ${NEXUS_HOME}/etc/ssl \
 && ln -s ${NEXUS_DATA}/etc/ssl ${NEXUS_HOME}/etc/ssl \
 && chown -R nexus:nexus ${NEXUS_DATA}

# generate nexus key
RUN /opt/java/bin/keytool -genkeypair \
        -keystore ${NEXUS_KEYSTORE}/keystore.jks \
        -storepass ${KEYSTOREPASSWORD} \
        -keypass ${KEYMANAGERPASSWORD} \
        -alias jetty -keyalg RSA -keysize 512 -validity 3650  \
        -dname "CN=*.local, OU=Example, O=Sonatype, L=Unspecified, ST=Unspecified, C=US" \
        -ext "SAN=DNS:nexus.local,IP:127.0.0.1" -ext "BC=ca:true"

# configure nexus ssl - https
RUN sed -i 's/<Set name="KeyStorePath">.*<\/Set>/<Set name="KeyStorePath">\/nexus-data\/etc\/ssl\/keystore.jks<\/Set>/g' ${NEXUS_HOME}/etc/jetty/jetty-https.xml \
    && sed -i 's/<Set name="KeyStorePassword">.*<\/Set>/<Set name="KeyStorePassword">changeit<\/Set>/g' ${NEXUS_HOME}/etc/jetty/jetty-https.xml \
    && sed -i 's/<Set name="KeyManagerPassword">.*<\/Set>/<Set name="KeyManagerPassword">changeit<\/Set>/g' ${NEXUS_HOME}/etc/jetty/jetty-https.xml \
    && sed -i 's/<Set name="TrustStorePath">.*<\/Set>/<Set name="TrustStorePath">\/nexus-data\/etc\/ssl\/keystore.jks<\/Set>/g' ${NEXUS_HOME}/etc/jetty/jetty-https.xml \
    && sed -i 's/<Set name="TrustStorePassword">.*<\/Set>/<Set name="TrustStorePassword">changeit<\/Set>/g' ${NEXUS_HOME}/etc/jetty/jetty-https.xml
        
VOLUME ${NEXUS_DATA}

# TODO: add 18443 to exposed ports list 
EXPOSE 8443
USER nexus
WORKDIR ${NEXUS_HOME}

ENV JAVA_MAX_MEM=1200m \
  JAVA_MIN_MEM=1200m \
  EXTRA_JAVA_OPTS=""

CMD ["bin/nexus", "run"]
