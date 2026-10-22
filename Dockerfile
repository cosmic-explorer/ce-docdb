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

# COPY merges with the frozen base image and cannot delete files it inherited,
# so scripts retired by the security hot-fixes are removed explicitly:
# MigrationHelper (H6, unauthenticated bulk publish), test.pl (L17, Sentry
# DSN), three LIGO-era diagnostics that echoed request environment and
# identity to the browser or to /tmp (auth.sh, test.sh, remote_user.sh), and
# the P&P review hook that exported document metadata to a LIGO host (H10).
RUN rm -f /usr1/www/cgi-bin/private/DocDB/MigrationHelper \
          /usr1/www/cgi-bin/private/DocDB/ProcessPNPReview \
          /usr1/www/cgi-bin/test.pl \
          /usr1/www/cgi-bin/private/DocDB/auth.sh \
          /usr1/www/cgi-bin/private/DocDB/test.sh \
          /usr1/www/cgi-bin/private/DocDB/remote_user.sh

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

# PHP is not used by the DCC (Perl CGI). The base image carried mod_php
# 7.2.10 from the defunct IUS repository (end of life 2020, no fix for the
# 2026 PHP2Shell flaws exists below 8.2), a MediaWiki 1.29.1 tree whose
# database host no longer exists, two phpMyAdmin trees, and symlinks from the
# web root into /usr1/www. Remove the interpreter, the module and the PHP
# applications, and stop advertising PHP in the Server header
# (ServerTokens Prod in etc/httpd/conf/httpd.conf).
RUN rpm -e $(rpm -qa 'php72u*' 'mod_php72u*') && \
    rm -rf /usr1/www/html/mediawiki-1.29.1 /usr1/www/html/wiki \
           /usr1/www/html/phpMyAdmin-2.11.9.2 /usr1/www/html/phpMyAdmin-4.0.10.20-english \
           /usr1/www/html/php___myadmin \
           /etc/httpd/conf.d/php.conf /etc/httpd/conf.modules.d/15-php.conf \
           /var/lib/php && \
    ! test -e /usr/bin/php && ! test -e /usr/lib64/httpd/modules/libphp7.so

# ENTRYPOINT (supervisord) is inherited from the base image.
