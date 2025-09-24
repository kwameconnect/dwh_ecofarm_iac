import uuid

ts = "2025-09-21T11:50:00Z"
uuid1 = uuid.uuid5(uuid.NAMESPACE_DNS, ts)
uuid2 = uuid.uuid5(uuid.NAMESPACE_DNS, ts)
print(uuid1 == uuid2)  # True (deterministic)
