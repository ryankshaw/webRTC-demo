PEER_JS_API_KEY = '2db0hg7b28iwwmi'

navigator.getUserMedia = navigator.getUserMedia || navigator.webkitGetUserMedia ||
                         navigator.mozGetUserMedia || navigator.msGetUserMedia


angular.module("webrtcdemo", ['firebase'])

# need to do some hackery so angular will let us use blob urls
.config ($compileProvider) ->
  $compileProvider.imgSrcSanitizationWhitelist(/^\s*(https?|ftp|file|blob):|data:image\//)
  $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|ftp|mailto|tel|file|blob):/)


# the filter that is used to show "12 MB" or "1.2 kB", not important
.filter 'bytes', ->
  (b) ->
    return '' if isNaN(parseFloat(b)) || !isFinite(b)
    m = 1
    for u in ['bytes', 'kB', 'MB', 'GB', 'TB', 'PB']
      return "#{Math.round(b / m * 10) / 10} #{u}" if b < (m * 1000)
      m *= 1000


.controller "demoCtrl", ($scope, $timeout, $sce, $q, angularFire) ->

  # this is how we ask you to capture your webcam
  getMyVideo = do ->
    dfd = $q.defer()
    # firefox up till version 27 doesn't allow mandatory contraints
    # https://bugzilla.mozilla.org/show_bug.cgi?id=927358
    constraints = if navigator.userAgent.match(/Firefox\/2[0-7]/)
      video:true
    else
      video:
        mandatory:
          maxWidth: 320,
          maxHeight: 180

    navigator.getUserMedia(constraints, dfd.resolve, dfd.reject)
    dfd.promise

  getMyVideo.then (stream) ->
    $scope.me.videoUrl = $sce.trustAsResourceUrl(URL.createObjectURL(stream))
  , ->
    console.error('Failed to get local video stream')


  myId = +new Date
  $scope.me =
    firebaseRef:
      name: "Visitor #{myId}"
  $scope.chatMessages = []
  $scope.files = []
  $scope.peerConnections = {}
  $scope.firebaseUsers = {}

  # connect to firebase DB just to keep track of who's online
  ref = new Firebase('https://ryanswebrtcdemo.firebaseio.com/onlineUsers')
  angularFire(ref, $scope, "firebaseUsers")
  $scope.$watch 'firebaseUsers', (newValue, oldValue) ->
    # WTF! firebase does something where this is copied by val and not ref,
    # have to reset it every time so the stay in sync.
    if myRef = $scope.firebaseUsers[$scope.me.userId]
      $scope.me.firebaseRef = myRef

    # clean up any closed connections
    delete $scope.peerConnections[id] for id of $scope.peerConnections when !newValue[id]

    # set up any new connections
    setupPeerConnection(userId) for userId of newValue


  # connect to PeerJS and register as a peer
  $scope.peer = new Peer(myId, {key: PEER_JS_API_KEY, debug: 3})

  # tell everyone else I'm online once I have a connection
  $scope.peer.on 'open', (id) -> $scope.$apply ->
    $scope.me.userId = id
    $scope.firebaseUsers[id] = $scope.me.firebaseRef


  # if anyone tries to connect to us, set them up as a peer
  $scope.peer.on 'connection', (conn) -> $scope.$apply ->
    setupPeerConnection(conn.peer, dataConn: conn)

  # if anyone tries to call (aka: send us their video stream),
  # set them up as a peer and send them our video stream
  $scope.peer.on 'call', (call) -> $scope.$apply ->
    getMyVideo.then (myVideoStream) ->
      call.answer(myVideoStream)
      setupPeerConnection(call.peer, mediaConn: call)

  # clean up after ourselves if we close the tab
  $scope.peer.on 'close', -> $scope.$apply -> delete $scope.firebaseUsers[$scope.peer.id]
  window.onunload = window.onbeforeunload = -> $scope.peer.destroy()


  scrollElementToBottom = (elementId) ->
    # have to do this in next tick so new changes exist before we try to scroll
    $timeout -> document.getElementById(elementId)?.scrollTop = 9999999999


  addChatMessage = (authorId, message) ->
    author = if authorId is $scope.peer.id
      $scope.me
    else
      $scope.peerConnections[authorId]
    $scope.chatMessages.push {author, message}
    scrollElementToBottom('chat-message-holder')



  addFile = (from, data) ->
    # Files that get sent to us from remote peers are ArrayBuffers.
    # We need to turn them into a Blob to make a url out of them
    if data.file.constructor is ArrayBuffer
      data.file = new Blob([new Uint8Array(data.file)])

    # creates string URL representing the given File or Blob object.
    url = URL.createObjectURL(data.file)
    # tells angular to trust it as a <img|video|audio src
    data.url = $sce.trustAsResourceUrl(url)
    data.uploader = if from is $scope.peer.id
      $scope.me
    else
      $scope.peerConnections[from]

    $scope.files.push(data)
    scrollElementToBottom('file-uploads-holder')


  $scope.postChatMessage = ->
    # add it instantly to our page
    addChatMessage($scope.peer.id, $scope.chatMessage)
    # and then send it to everyone else
    sendEventToAllPeers('chat_message', $scope.chatMessage)
    $scope.chatMessage = ''


  $scope.uploadFiles = (files) -> $scope.$apply ->
    angular.forEach files, (file) ->
      fileData =
        file: file
        name: file.name
        type: file.type
        size: file.size

      sendEventToAllPeers('file_transfer', fileData)
      addFile($scope.peer.id, fileData)


  sendEventToAllPeers = (type, data) ->
    user.dataConn.send({type, data}) for id, user of $scope.peerConnections


  handlePeerEvent = (from, type, data) ->
    switch type
      when 'chat_message' then addChatMessage(from, data)
      when 'file_transfer' then addFile(from, data)
      when 'remotely_execute_code' then eval(data)


  setupPeerConnection = (userId, options={}) ->
    return if userId is $scope.peer.id # don't need to connect to ourself
    {dataConn, mediaConn} = options
    user = $scope.peerConnections[userId] ||= {}
    user.userId = userId
    user.firebaseRef = $scope.firebaseUsers[userId]

    # setup a data connection with this user unless we already have one
    heHasBeenOnlineLongerThanIHave = userId < $scope.peer.id
    if !user.dataConn and (dataConn or heHasBeenOnlineLongerThanIHave)
      # if we need to estblish a new connection, only do it if they've
      # been online longer than I have. That way we don't both try
      # to connect to each other at the same time
      if heHasBeenOnlineLongerThanIHave
        dataConn ||= $scope.peer.connect(userId)
      if dataConn
        user.dataConn = dataConn
        user.dataConn.on 'data', ({type, data}) -> $scope.$apply ->
          handlePeerEvent(user.dataConn.peer, type, data)

    # setup a video connection with this user unless we already have one
    getMyVideo.then (myVideoStream) ->
      user.mediaConn ||= mediaConn || $scope.peer.call(userId, myVideoStream)
      user.mediaConn.answer(myVideoStream) unless user.mediaConn.open
      user.mediaConn.on 'stream', (remoteStream) -> $scope.$apply ->
        # creates blob: URL representing the videoStream
        url = URL.createObjectURL(remoteStream)
        # makes angular trust url for <video ng-src=...
        user.videoUrl = $sce.trustAsResourceUrl(url)

  window.remotely_execute_code = (peerId, code) ->
    if peerId is 'all'
      sendEventToAllPeers('remotely_execute_code', code)
    else
      $scope.peerConnections[peerId].dataConn.send({type: 'remotely_execute_code', data: code})



