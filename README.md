# Nano Cluster

This project is the source code for a tiny cluster of ESP32 devices I built.

The cluster contains an arbitrary amount of ESP32's that will discover eachother
via UDP broadcasting. They elect a leader via simple node name ordering where
the biggest wins (i.e., no partition tolerance).

The leader has a work queue where items can be submitted. There is an example
implementation of finding the amount of primes in a given range. Each worker
node will pick up tasks from the leader's queue and compute them, and report
back the result.




Dashboard ![The Nano Cluster overview dashboard: a header showing 4/5 nodes online with nano@192.168.4.61 as leader and no work waiting or in flight, a form for submitting a prime-finding job over a range, three completed prime jobs each reporting 9592 primes, and per-node cards listing each node's status, queue, and discovered peers.](img/dashboard.png)

## Learnings

The ESP32s have very little memory and do not deal with multiple socket
connections well. This meant that I could for example not send many concurrent
web requests from the dashboard. The dashboard therefore completely serializes
all its requests to not make the ESP32 go OOM.

A good design for the queue (or the one I made, in any case) is not always the best design for embedded systems. It works really well, but it eats memory a lot. There are plenty of ways to reduce memory footprint, but they require some extra attention. You don't notice these things on your Macbook with 143343 cores and 233535 zetabyte of RAM.

AtomVM is a really good piece of software, kudos to the authors. I found some bugs that I plan to report and improve the system.

This was super fun to build. Most of the primitives you would expect from Erlang just work out of the box, and there are very little surprises. Some of the stdlib functions are not available (e.g., `Map.pop/2`), maybe I can contribute that too.


## Todo (which I will probably never do)

 - The jobs can actually be lazy. The queue can generate the items on-demand from the jobs in the queue, so that no task sits in the queue waiting to be picked up, and eating memory.

 - All workers can in theory also expose a websocket to send real-time updates to the dashboard, rather than the dashboard polling them all the time.

 - The vm sometimes dies due to unexpected issues. I'm sure I can trivially fix this, but I don't really know how yet.


## Models

I've 3d-printed a housing to store the esp32 in, and the model can be found in the `models` repo. I printed without supports with 0.25mm nozzle. 0.4 was a bit rough. The model fits for an ESP32-DevkitM-1.

Dashboard ![A green 3D-printed vertical tower made of six stacked, ventilated modules—each perforated with a grid of small holes—housing a column of ESP32 development boards, with their USB ports visible along the left edge. The tower stands on a workbench, connected by jumper wires to a white breadboard on the right. The picture also shows my workbench is an absolute mess and I should be ashamed.](img/cluster.jpg)