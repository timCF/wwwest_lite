WwwestLite
==========

- impl config for your app
- impl callback like in example module

```
curl -d '{"cmd":"echo","args":"hello"}' http://127.0.0.1:9866
{"ans":"hello"}

curl -d '{"cmd":"time"}' http://127.0.0.1:9866
{"ans":1444312746723}
```