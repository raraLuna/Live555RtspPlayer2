Live555RtspPlayer2 개요 
 - Live555Streaming Server와 RTSP 통신으로 영상 데이터를 전송받아 Data 처리를 통해 비디오 영상과 오디오를 parsing 및 rendering하여 플레이합니다.

[ViewController]
1. UI 세팅 및 rtsp 통신을 처리할 url 처리. 
         // 카메라 서버와 통신하여 카메라 디바이스 실시간 스트리밍 시에 진행되는 로직
    1. login() : 로그인 정보를 바탕으로 서버에 로그인 시행 API
    2. reqVod() : 서버에 카메라 정보를 바탕으로 실시간 스트리밍 전송을 요청 API
    3. canBeStreaming : 현재 카메라가 실시간 스트리밍이 가능한 상태인지 확인 API
    4. getStreamUrl() : 스트리밍이 가능한 경우 url주소를 서버에게 받는 API

2. 영상을 전송받는 URL로 RTSP 통신 시작
    1. RTSPClient class 객체인 rtspClient 선언
    2. 서버와 client의 connect 시도 
    3. rtspClient를 통하여 OPTION, DESCRIPTION, SETUP, PLAY, TEARDOWN 요청을 보내고 response를 받음
    4. 서버의 response에 따라 다음 진행할 작업 관리

3. STOP 버튼이 눌리면 rtspClient 작업 중단

[RTSPClient]
1. 서버와 직접적인 socket 통신을 진행. 
    1. Darwin class 사용하여 socket 생성 및 Data receive
    2. sendRequest(), readResponse(), closeConnection() 처리
    3. sendOption(), sendDescription(), sendSetup(), sendPlay(), sendTearDown() request 내용 처리
    4. startReceivingData(): PLAY요청을 보낸 뒤 서버로부터 데이터를 전송 받음 (서버와 연결되어있는 동안 계속)
        1. 1byte 단위씩 읽으며 ‘$’문자 찾음 
            1. ‘$’ 찾으면 뒤에 이어지는 RTP 정보 (channel, length byte) 읽음
            2. lengthByte 만큼 Data 읽음
            3. Data의 처음 12byte (RTP Header)를 parsing
            4. payloadType을 확인하여 Video / Audio 구분하여 각 parse 함수를 호출함
        2. 1byte 단위씩 읽으면서 ‘R’ 문자 읽음
            1. ‘R’ 뒤에 이어지는 문자가 ‘TSP’ 인지 확인 (RTSP Reponse 응답인지 확인)
            2. [13, 10, 13, 10] 이 나올때까지의 RTP Data 읽음 (‘\r\n\r\n’)
    5. parseVideo() 
        1. description 정보로 얻은 encode type에 따라 h264, h265 구분하여 처리
            1. h264인 경우
                1. RTP packet에서 nalUnit Data를 얻어서 SPS, PPS 찾아서 정보 저장
                2. Video decoding을 위해서 nalData를 Queue에 저장
            2. h265인 경우
                1. RTP packet에서 nalUnit Data를 얻음
                2. nalUnitType에 따라서 VPS, SPS, PPS 정보 저장
                3. VPS, SPS, PPS로 전송되는 정보가 없는 경우 description에서 저장한 정보 사용
                4. Video decoding을 위해서 nalData를 Queue에 저장
    6. parseAudio()
        1. Audio RTP Packet을 처리
        2. Hedaer 처리 (필요 시 ADTS Header 생성하여 추가) 한 뒤 payload Data Queue에 저장
    7. 그 외 
        1. Description, session 정보를 parsing하여 저장, Header parsing 등의 작업 진행 

[RtpH264Parser]
1. H264로 분류된 RTP Packet의 parsing 작업 담당
    1. nalType 확인하여 FU_A 타입인 경우 처리 진행 (그외 타입 지원하지 않음)
        1. Fu Header의 packFlag를 확인하여 start /  middle / end packet 처리 진행 
        2. start packet인 경우 Fu_A Header에서 원래의 nalType을 복구한 뒤 버퍼에 저장, 
        3. middle packet인 경우 저장되고 있는 nal packet Data 버퍼에 이어서 저장.
        4. end packet인 경우 버퍼 마지막으로 저장한 뒤 [0, 0, 0, 1] 붙여주고 전체 버퍼값 nalUnit Data로 반환

[RtpH265Psrser]
1. H265로 분류된 RTP Packet의 parsing 작업 담당
    1. nalType 확인하여 FU타입인 경우 처리 진행 (AP 타입 지원하지 않음)
        1. Fu Header와 marker 정보를 확인하여 start /  middle / end packet 처리 진행 
        2. start packet인 경우 Fu Header에서 tid, nalType을 복구한 뒤 버퍼에 저장, 
        3. middle packet인 경우 저장되고 있는 nal packet Data 버퍼에 이어서 저장.
        4. end packet인 경우 버퍼 마지막으로 저장한 뒤 [0, 0, 0, 1] 붙여주고 전체 버퍼값 nalUnit Data로 반환

[H264Decoder], [H265Decoder]
1. CMFormatDescription, VTDecompressionSession을 사용하여 영상 디코딩 처리 
    1. decompressionOutputCallback : 디코딩 완료되면 결과물을 처리
    2. decode() : 디코딩 시작 함수. Queue에 저장 된 video Data 불러옴
    3. setupDecoder() : 디코딩에 사용할 VTDecompressionSession을 생성, 콜백 초기화 작업
    4. decodeFrame() : 생성된 VTDecompressionSession을 이용하여 nalData를 CMBlockBuffer로 변환
                                          BlockBuffer를 CMSampleBuffer로 만든 뒤 DecompressionSession을 이용하여 Frame Decoding
	5. Decoding 완료되면 결과물을 콜백함수로 전달 -> 실패 or 성공 
	6. 성공 시 결과물 (PixelBuffer)로 rendering 시작
2. H265Decoder의 경우 Decoing 순서와 Frame 순서를 확인하기 위한 과정 추가 필요함 

[PCMPlayer]
1. AVAudioEngine(), AVAudioPlayerNode() 사용하여 nalData를 재생 처리
    1. startPlayback() : inpuFormat과 outputFormat을 정의, engine connect, 출력에 사용할 timer 사용(끊김 방지)
					    audioEngine start, playerNode.play로 코드 상 재생 시작
    2. feedBuffer() : Queue에서 audio Data를 받아와서 AVAudioPCMBuffer로 변환 후 playerNode에 schedule 처리 
   				      -> 실질적인 오디오 재생 시작 됨
	3. 즉, 타이머를 설정하여 일정 오디오 데이터가 쌓이면 재생이 되도록 함으로써 데이터 전송 시간차에 따른 끊김 현상을 방지함 

[MetalRender], [vertexShader]
1. 디코딩 된 PixelBuffer의 내용을 전달 받아서 Metal를 이용하여 프레임을 화면에 그림
    1. init() : 초기화 함수에서 vertex,, textCored 를 세팅 (화면에 그림을 그릴 때 사용할 좌표 설정)
 			vertexShader 연결하고 MTLVertexDescriptor 위치 좌표, 텍스쳐 좌표 세팅 
	2. draw() : init()에서 세팅된 정보를 바탕으로 pixelBuffer의 y Data, uv Data를 화면에 그림. 


