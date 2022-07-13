docker-compose down -v --remove-orphans
docker-compose build
docker-compose run --rm start_dependencies
docker-compose run --rm mail_log /bin/sh -c 'sql/initdb.sh'
docker-compose run --rm mail_log /bin/sh -c 'plackup --host 0.0.0.0 --port 5000 /app/bin/app.psgi'
docker-compose down -v --remove-orphans