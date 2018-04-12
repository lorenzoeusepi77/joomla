FROM php:7.2-apache
LABEL maintainer="Michael Babker <michael.babker@joomla.org> (@mbabker)"

#RUN DOCKER NO ROOT
# Add none root user
#RUN  useradd admin && echo "admin:admin" | chpasswd && adduser admin sudo
RUN apt-get update; \
    apt-get install -y sudo && \
    adduser user && \
    echo "user ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/user && \
    chmod 0440 /etc/sudoers.d/user

# Disable remote database security requirements.
ENV JOOMLA_INSTALLATION_DISABLE_LOCALHOST_CHECK=1

# Enable Apache Rewrite Module
#RUN rm /etc/apache2/mods-enabled/rewrite.load
RUN a2enmod rewrite

# Install PHP extensions
RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libbz2-dev \
		libjpeg-dev \
		libldap2-dev \
		libmemcached-dev \
		libpng-dev \
		libpq-dev \
	; \
	\
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
	docker-php-ext-configure ldap --with-libdir="lib/$debMultiarch"; \
	docker-php-ext-install \
		bz2 \
		gd \
		ldap \
		mysqli \
		pdo \
		pdo_mysql \
		pdo_pgsql \
		pgsql \
		zip \
	; \
	\
	pecl install \
		APCu-5.1.10 \
		memcached-3.0.4 \
		redis-3.1.6 \
	; \
	\
	docker-php-ext-enable \
		apcu \
		memcached \
		redis \
	; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

VOLUME /var/www/html

# Define Joomla version and expected SHA1 signature
ENV JOOMLA_VERSION 3.8.6
ENV JOOMLA_SHA1 769d86c00b3add41b1fa6c85f3ec823a07df88d1

# Download package and extract to web volume
RUN curl -o joomla.tar.bz2 -SL https://github.com/joomla/joomla-cms/releases/download/${JOOMLA_VERSION}/Joomla_${JOOMLA_VERSION}-Stable-Full_Package.tar.bz2 \
	&& echo "$JOOMLA_SHA1 *joomla.tar.bz2" | sha1sum -c - \
	&& mkdir /usr/src/joomla \
	&& tar -xf joomla.tar.bz2 -C /usr/src/joomla \
	&& rm joomla.tar.bz2 \
	&& chown -R www-data:www-data /usr/src/joomla

# Copy init scripts and custom .htaccess
COPY docker-entrypoint.sh /entrypoint.sh
COPY makedb.php /makedb.php

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
