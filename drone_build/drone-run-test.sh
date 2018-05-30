docker ps -a | grep kong
result=$?
echo "check test env with code: ${result}"

if [ "${result}" -eq "0" ] ; then
    echo -e "\nold container service running, delete it"
    docker stop kong kong-database
    docker rm kong kong-database
else
    echo -e "\ncheck test env OK"
fi

echo -e "\n<-- start to run cassandra -->"
docker run -d --rm --name kong-database \
    -p 9042:9042 \
    cassandra:3

# wait for cassandra service up
while [[ $(docker exec -it kong-database nodetool netstats | grep 'Mode') != *"NORMAL"* ]]; do
    sleep 3
done

echo -e "\n<-- start to do db migration -->"
docker run --rm \
    --link kong-database:kong-database \
    -e "KONG_DATABASE=cassandra" \
    -e "KONG_PG_HOST=kong-database" \
    -e "KONG_CASSANDRA_CONTACT_POINTS=kong-database" \
    -v "kong:/usr/local/share/lua/5.1/kong" \
    kong kong migrations up

echo -e "\n<-- start to run kong -->"
docker run -d --rm --name kong \
    --link kong-database:kong-database \
    -e "KONG_DATABASE=cassandra" \
    -e "KONG_CASSANDRA_CONTACT_POINTS=kong-database" \
    -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
    -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
    -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
    -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
    -e "KONG_ADMIN_LISTEN=0.0.0.0:8001" \
    -e "KONG_ADMIN_LISTEN_SSL=0.0.0.0:8444" \
    -v "kong:/usr/local/share/lua/5.1/kong" \
    -p 8000:8000 \
    -p 8443:8443 \
    -p 8001:8001 \
    -p 8444:8444 \
    kong:0.13.1
