# Layer the code and configuration tracked in this repository on top of the
# frozen production base image. The base image (cosmicexplorer/dcc:3.3.0) was
# built once from the Caltech DCC disk image by ce-it-infrastructure/dcc and
# must never be rebuilt or retagged; this repository is the source of truth
# for everything that sits on top of it.
#
# Build with scripts/build-image.sh, which tags the result with the git commit
# it was built from. See UPDATING.md.

ARG BASE_IMAGE=cosmicexplorer/dcc:3.3.0
FROM ${BASE_IMAGE}

# DocDB Perl CGI application (private + public instances). Symlinks in the
# public instance keep their absolute targets and are copied as symlinks.
COPY usr1/www/cgi-bin/ /usr1/www/cgi-bin/

# Web root pieces that live in the image. usr1/www/html/DocDB and
# usr1/www/html/public are host bind mounts and are excluded by .dockerignore.
COPY usr1/www/html/ /usr1/www/html/

# Apache, Shibboleth SP and embedded discovery service configuration.
# shibboleth2.xml, attribute-map.xml and inc-md-cert.pem are overridden at run
# time by host bind mounts; the SP signing cert/key come from Docker secrets
# (start-shibd.sh) and are excluded by .dockerignore. inc-md-cert-mdq.pem is
# referenced by shibboleth2.xml and must be present in the image.
COPY etc/httpd/conf/ /etc/httpd/conf/
COPY etc/httpd/conf.d/ /etc/httpd/conf.d/
COPY etc/httpd/conf.modules.d/ /etc/httpd/conf.modules.d/
COPY etc/shibboleth/ /etc/shibboleth/
COPY etc/shibboleth-ds/ /etc/shibboleth-ds/

# Container entrypoint scripts and cron jobs.
COPY usr/local/ /usr/local/
COPY etc/cron.daily/ /etc/cron.daily/

# ENTRYPOINT (supervisord) is inherited from the base image.
