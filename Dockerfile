FROM registry.ci.openshift.org/ocp/builder:rhel-8-golang-1.19-openshift-4.13 AS builder
ARG TAGS=""
WORKDIR /go/src/github.com/openshift/machine-config-operator
COPY . .
# FIXME once we can depend on a new enough host that supports globs for COPY,
# just use that.  For now we work around this by copying a tarball.
RUN make install DESTDIR=./instroot && tar -C instroot -cf instroot.tar .

FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang-1.19-openshift-4.13 AS rhel9-builder
ARG TAGS=""
WORKDIR /go/src/github.com/openshift/machine-config-operator
COPY . .
RUN make install DESTDIR=./instroot

FROM registry.ci.openshift.org/ocp/4.13:base
ARG TAGS=""
COPY --from=builder /go/src/github.com/openshift/machine-config-operator/instroot.tar /tmp/instroot.tar
RUN cd / && tar xf /tmp/instroot.tar && rm -f /tmp/instroot.tar
COPY --from=rhel9-builder /go/src/github.com/openshift/machine-config-operator/instroot/usr/bin/machine-config-daemon /usr/bin/machine-config-daemon.rhel9
COPY install /manifests

RUN if [ "${TAGS}" = "fcos" ] || [ "${TAGS}" = "scos" ]; then \
    # comment out non-base/extensions image-references entirely for fcos/scos
    sed -i '/- name: rhel-coreos-/,+3 s/^/#/' /manifests/image-references && \
    # also remove extensions from the osimageurl configmap (if we don't, oc won't rewrite it, and the placeholder value will survive and get used)
    sed -i '/baseOSExtensionsContainerImage:/ s/^/#/' /manifests/0000_80_machine-config-operator_05_osimageurl.yaml; fi && \
    # rewrite image names for fcos/scos
    # XXX: pin nmstate to 2.2.9 until we've replaced `--inspect` (see https://github.com/openshift/machine-config-operator/pull/3706)
    if [ "${TAGS}" = "fcos" ]; then sed -i 's/rhel-coreos/fedora-coreos/g' /manifests/*; \
    elif [ "${TAGS}" = "scos" ]; then sed -i 's/rhel-coreos/centos-stream-coreos-9/g' /manifests/*; fi && \
    if ! rpm -q util-linux; then dnf install -y util-linux; fi && dnf -y install nmstate-2.2.9-6.rhaos4.13.el8 && dnf clean all && rm -rf /var/cache/dnf/*
COPY templates /etc/mcc/templates
ENTRYPOINT ["/usr/bin/machine-config-operator"]
LABEL io.openshift.release.operator true
