sleep 10

echo -e "\n<-- start to stop db & kong -->"
docker stop kong-database kong

echo -e "\n<-- start to rm db & kong -->"
docker rm kong-database kong
