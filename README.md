# GCDSimpleSocketServer
Demonstrates the usage of GCD blocks for a simple embedded TCP Socket echo server.

All runs in the main thread in an event driven fashion, hence no hassles with thread sync.

It's easier to program in comparison with CFSocket/NSStream (see the cfsocket repo)

Run the program with Xcode in the simulator and use it with

`echo hallo | nc localhost 9100`
