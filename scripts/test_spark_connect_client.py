# Requires pyspark to be installed in your Python environment
import time
from pyspark.sql import SparkSession

start = time.time()
spark = SparkSession.builder.remote("sc://localhost:15002").getOrCreate()
connect_time = time.time()
print("Connected to Spark Connect server in {:.3f} seconds".format(connect_time - start))

# Optionally, run a simple query
result = spark.range(10).count()
query_time = time.time()
print("Query result:", result)
print("Time to first query: {:.3f} seconds".format(query_time - start))

spark.stop() 