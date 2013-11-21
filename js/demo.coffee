API_KEY = '2db0hg7b28iwwmi'
PRESENTING_PEERS_ID = 'presenterwerwe'

# Special code that only the presenter needs to run
if location.search.match('presenter')
  allParticipants = {}
  tellEveryoneSomeoneNewIsOnline = ->
    ids = Object.keys allParticipants
    c.send(type: 'user_added', data: ids) for id, c of allParticipants

  presentingPeer = new Peer(PRESENTING_PEERS_ID, {key: API_KEY, debug: 3})
  presentingPeer.on 'connection', (conn) ->
    allParticipants[conn.peer] = conn
    tellEveryoneSomeoneNewIsOnline()




angular.module("webrtcdemo", [])

# need to do some hackery so angular will let us use blob urls
.config ($compileProvider) ->
  $compileProvider.imgSrcSanitizationWhitelist(/^\s*(https?|ftp|file|blob):|data:image\//)
  $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|ftp|mailto|tel|file|blob):/)


# the filter that is used to show "12 MB" or "1.2 kB"
.filter 'bytes', ->
  units = ['bytes', 'kB', 'MB', 'GB', 'TB', 'PB']
  (bytes, precision = 1) ->
    return '' if isNaN(parseFloat(bytes)) || !isFinite(bytes)
    mult = 1
    for unitname in units
      if bytes < (mult * 1000)
        quantity = bytes / mult
        # round to at most 1 decimal
        quantity = Math.round(quantity * 10) / 10
        return "#{quantity} #{unitname}"
      mult *= 1000
    return bytes


.controller "demoCtrl", ($scope, $timeout, $sce, $q) ->

  # this is how we ask you to capture your webcam
  getMyVideo = do ->
    dfd = $q.defer()
    navigator.getMedia = navigator.getUserMedia ||
                         navigator.webkitGetUserMedia ||
                         navigator.mozGetUserMedia ||
                         navigator.msGetUserMedia

    navigator.getMedia({video: true, audio: true}, dfd.resolve, dfd.reject)
    dfd.promise

  getMyVideo.then (stream) ->
    $scope.me.videoUrl = $sce.trustAsResourceUrl(URL.createObjectURL(stream))
  , console.error.bind(console, 'Failed to get local stream')



  $scope.peerConnections = {}
  $scope.chatMessages = []
  $scope.files = []
  $scope.me = {}

  $scope.peer = new Peer({key: API_KEY, debug: 3})
  $scope.peer.on 'open', (id) -> $scope.$apply -> $scope.me.userId = id

  # if anyone tries to connect to us, set them up as a peer
  $scope.peer.on 'connection', (conn) -> $scope.$apply ->
    setupPeerConnection(conn.peer, dataConn: conn)

  # if anyone tries to call (aka: send us their video stream),
  # set them up as a peer and send them our video stream
  $scope.peer.on 'call', (call) -> $scope.$apply ->
    getMyVideo.then (myVideoStream) ->
      call.answer(myVideoStream)
      setupPeerConnection(call.peer, mediaConn: call)

  console.log "Connecting to the presenter so he can tell me who's online."
  presenterConn = $scope.peer.connect(PRESENTING_PEERS_ID, reliable: true)
  presenterConn.on 'data', ({type, data}) -> $scope.$apply ->
    console.log 'presenter says these people are online', data...
    setupPeerConnection(user) for user in data


  addChatMessage = (authorId, message) ->
    author = if authorId is $scope.peer.id
      $scope.me
    else
      $scope.peerConnections[authorId]
    $scope.chatMessages.push {author, message}
    # after we add the new message, scroll to the bottom
    $timeout -> document.getElementById('chat-message-holder')?.scrollTop = 9999999999


  addFile = (from, data) ->
    # Files that get sent from us from remote peers are ArrayBuffers.
    # We need to turn them into a Blob to make a url out of them
    if data.file.constructor is ArrayBuffer
      dataView = new Uint8Array(data.file)
      data.file = new Blob([dataView])

    # creates string URL representing the given File or Blob object.
    url = URL.createObjectURL(data.file)
    # tells angular to trust it as a <img|video|audio src
    data.url = $sce.trustAsResourceUrl(url)

    data.previewType = if data.type.match('image')
      'image'
    else if data.type.match('video')
      'video'
    else if data.type.match('audio')
      'audio'

    data.author = if from is $scope.peer.id
      $scope.me
    else
      $scope.peerConnections[from]

    $scope.files.push(data)
    # after we add the new file, scroll to the bottom
    $timeout -> document.getElementById('file-uploads-holder')?.scrollTop = 9999999999


  $scope.postChatMessage = ->
    # add it instantly to our page
    addChatMessage($scope.peer.id, $scope.chatMessage)
    # and then send it to everyone else
    sendEventToAllPeers('chat_message', $scope.chatMessage)
    $scope.chatMessage = ''


  $scope.uploadFiles = (files) -> $scope.$apply ->
    angular.forEach files, (file) ->
      fileData =
        file:file
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


  setupPeerConnection = (userId, options={}) ->
    {dataConn, mediaConn} = options
    user = $scope.peerConnections[userId] ||= {}
    user.userId = userId

    # setup a data connection with this user unless we already have one
    unless user.dataConn
      user.dataConn = dataConn || $scope.peer.connect(userId, reliable: true)
      user.dataConn.on 'data', ({type, data}) -> $scope.$apply ->
        handlePeerEvent(user.dataConn.peer, type, data)

    # setup a video connection with this user unless we already have one
    getMyVideo.then (myVideoStream) ->
      unless user.mediaConn
        user.mediaConn = mediaConn || $scope.peer.call(userId, myVideoStream)
      if user.mediaConn and not user.mediaConn.open
        user.mediaConn.answer(myVideoStream)
      user.mediaConn.on 'stream', (remoteStream) -> $scope.$apply ->
        # creates blob: URL representing the videoStream
        url = URL.createObjectURL(remoteStream)
        # makes angular trust url for <video ng-src=...
        user.videoUrl = $sce.trustAsResourceUrl(url)
