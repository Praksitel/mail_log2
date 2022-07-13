FROM perl:5.32

RUN apt-get update \
    && apt-get -y upgrade \
    && apt install -y libplack-perl locales libdancer2-perl cpanminus postgresql-client \
    && echo ru_RU UTF-8 >> /etc/locale.gen \
    && locale-gen \
    && cpanm --notest Dancer2::Template::Handlebars DateTime::Format::Pg Email::Valid DBD::Pg Data::Dumper \
    && apt autoclean

COPY . /app
WORKDIR /app

CMD  ["plackup", "--host", "0.0.0.0", "--port", "5000", "/app/bin/app.psgi"]