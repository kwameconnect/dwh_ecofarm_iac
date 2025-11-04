from diagrams import Diagram, Cluster
from diagrams.aws.compute import Lambda
from diagrams.aws.analytics import Glue, Cloudwatch
from diagrams.aws.integration import StepFunctions
from diagrams.custom import Custom

with Diagram("Eco-Farming Data Pipeline on AWS", show=False, direction="LR", filename="eco_farming_pipeline_diagram"):
    # Data sources
    weather = Custom("Weather API", "https://cdn-icons-png.flaticon.com/512/1163/1163661.png")
    solar = Custom("Solar Logs (kWh)", "https://cdn-icons-png.flaticon.com/512/869/869869.png")
    rain = Custom("Rain Collectors", "https://cdn-icons-png.flaticon.com/512/4151/4151022.png")

    with Cluster("Serverless Data Pipeline"):
        step_func = StepFunctions("Step Functions (Orchestrator)")
        lambda_ingest = Lambda("Lambda: Data Ingestion")
        glue_catalog = Glue("Glue: Transform & Catalog")
        step_func >> lambda_ingest
        step_func >> glue_catalog

    with Cluster("Monitoring & Analytics"):
        cloudwatch = Cloudwatch("CloudWatch Dashboards")
        metrics = Custom("CloudWatch Alarms & Metrics", "https://cdn-icons-png.flaticon.com/512/1827/1827504.png")
        cloudwatch >> metrics

    # Data flow
    weather >> step_func
    solar >> step_func
    rain >> step_func
    glue_catalog >> cloudwatch
