This is a demo of some things you can do with webRTC.
======================================================

### What it does

*   First, it uses [angularfilre](http://angularfire.com/) to connect
    to a real-time [firebase](https://www.firebase.com/) database to get a
    list of users on this page
*   Then, it uses a service called [PeerJS](http://peerjs.com) to simplify
    and abstract away some of the details of creating an RTCPeerConnection
    to ever other person viewing this page
*   Then, using that RTCPeerConnection it establishes a RTCDataChannel w/
    each peer, enabling communication of arbitrary data
    (in this case chat messages and file uploads)
*   Then, using [navigator.getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/Navigator.getUserMedia)
    it asks you to capture your webcam and it also establishes a p2p
    video connection with every other person viewing this page
*   It uses that video connection as the "live" avatar next
    to your name in your chat messages
*   When you send a chat message or upload files, it sends it
    _directly_ to each peer connected.  no messages, files, or video ever go
    through a server

**TL,DR:**
video/text chat & p2p file sharing using **no servers**
(except to get a list of who's online) and **no plugins (no flash)**

**[Read the Source](https://github.com/ryankshaw/webRTC-demo/blob/master/js/demo.coffee) on github.**
If you have any questions email me at my github username at gmail.
