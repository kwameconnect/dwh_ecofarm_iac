# /iac/redshift.tf
resource "aws_redshiftserverless_namespace" "weather_dwh" {
  namespace_name      = "weather-dwh-namespace"
  admin_username      = var.redshift_admin_username
  admin_user_password = var.redshift_admin_password
  db_name             = var.redshift_db_name
}

resource "aws_redshiftserverless_workgroup" "weather_dwh_workgroup" {
  namespace_name     = aws_redshiftserverless_namespace.weather_dwh.namespace_name
  workgroup_name     = "weather-dwh-workgroup"
  base_capacity      = 8  # Smallest capacity for Free Tier
  publicly_accessible = false
  security_group_ids  = [aws_security_group.redshift_sg.id]
  subnet_ids          = aws_subnet.private[*].id
}

resource "null_resource" "create_tables" {
  depends_on = [aws_redshiftserverless_workgroup.weather_dwh_workgroup]
  provisioner "local-exec" {
    command = <<EOF
    psql -h ${aws_redshiftserverless_workgroup.weather_dwh_workgroup.endpoint_address} 
     -U ${var.redshift_admin_username} -d ${var.redshift_db_name} -p 5439 
     -c "CREATE TABLE location_dim (
           location_id BIGINT PRIMARY KEY,
           city VARCHAR(100),
           country VARCHAR(100),
           latitude DECIMAL(9,6),
           longitude DECIMAL(9,6)
         );
         CREATE TABLE forecast_time_dim (
           forecast_time_id BIGINT PRIMARY KEY,
           date DATE,
           hour INT,
           day INT,
           month INT,
           year INT
         );
         CREATE TABLE download_time_dim (
           download_time_id BIGINT PRIMARY KEY,
           timestamp DATE,
           hour INT,
           day INT,
           month INT,
           year INT
         );
         CREATE TABLE forecast_data_fact (
           forecast_id BIGINT PRIMARY KEY,
           location_id BIGINT REFERENCES location_dim(location_id),
           time_id BIGINT REFERENCES download_time_dim(download_time_id),
           temperature_c DECIMAL(5,2),
           rain_mm DECIMAL(5,2),
           solarradiation_w DECIMAL(5,2),
           cloudcover INT,
           wind_speed_kmh DECIMAL(5,2),
           humidity DECIMAL(5,2),
           weather_condition VARCHAR(50),
           SORTKEY (time_id)
         );
         CREATE TABLE solar_energy_fact (
           energy_id BIGINT PRIMARY KEY,
           location_id BIGINT REFERENCES location_dim(location_id),
           time_id BIGINT REFERENCES download_time_dim(download_time_id),
           solarenergy_kwh DECIMAL(10,2),
           SORTKEY (time_id)
         );
         CREATE TABLE water_level_fact (
           measurement_id BIGINT PRIMARY KEY,
           location_id BIGINT REFERENCES location_dim(location_id),
           time_id BIGINT REFERENCES download_time_dim(download_time_id),
           water_level_mm DECIMAL(5,2),
           rain_collected_mm DECIMAL(5,2),
           SORTKEY (time_id)
         );"
EOF
       environment = {
         PGPASSWORD = var.redshift_admin_password
       }
     }
   }
