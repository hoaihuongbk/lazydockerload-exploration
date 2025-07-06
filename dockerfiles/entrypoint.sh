#!/bin/bash
set -e

# Function to wait for database
wait_for_db() {
    echo "Waiting for database..."
    while ! airflow db check; do
        sleep 1
    done
    echo "Database is ready!"
}

# Function to initialize Airflow
init_airflow() {
    echo "Initializing Airflow..."
    
    # Initialize the database
    airflow db init
    
    # Create admin user
    airflow users create \
        --username admin \
        --firstname Admin \
        --lastname User \
        --role Admin \
        --email admin@example.com \
        --password admin
    
    echo "Airflow initialized successfully!"
}

# Main execution
echo "Airflow container starting..."

# Set Airflow home
export AIRFLOW_HOME=/opt/airflow

# Create necessary directories
mkdir -p $AIRFLOW_HOME/{dags,logs,plugins}

# Initialize Airflow if database doesn't exist
if [ ! -f "$AIRFLOW_HOME/airflow.db" ]; then
    init_airflow
fi

# Wait for database if using external database
if [ "$AIRFLOW__DATABASE__SQL_ALCHEMY_CONN" != "" ]; then
    wait_for_db
fi

# If no arguments are provided, default to webserver
if [ $# -eq 0 ]; then
  set -- webserver
fi

# If the first argument is a known Airflow component, prepend 'airflow'
case "$1" in
  webserver|scheduler|worker|flower|version|celery|triggerer|standalone)
    set -- airflow "$@"
    ;;
esac

exec "$@" 