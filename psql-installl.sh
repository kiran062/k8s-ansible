echo "🐘 Installing PostgreSQL 16..."
if ! psql --version | grep -q "16"; then
  {
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    sudo apt-get update
    sudo apt-get -y install postgresql-16
    sudo systemctl enable postgresql
    sudo systemctl start postgresql
    sudo sed -i "s/^#listen_addresses =.*/listen_addresses = '*'/" /etc/postgresql/16/main/postgresql.conf
    echo "host all all 0.0.0.0/0 md5" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf > /dev/null
    sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'Honebi_P0stgr3s';"
    sudo systemctl restart postgresql
  } || echo "❌ PostgreSQL installation failed"
else
  echo "✅ PostgreSQL 16 already installed."
fi
