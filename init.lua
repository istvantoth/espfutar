stopId = 'BKK_F00815'

MAX7219_REG_NOOP        = 0x00
MAX7219_REG_DECODEMODE  = 0x09
MAX7219_REG_INTENSITY   = 0x0A
MAX7219_REG_SCANLIMIT   = 0x0B
MAX7219_REG_SHUTDOWN    = 0x0C
MAX7219_REG_DISPLAYTEST = 0x0F

MAX_CHARACTERS = {}
MAX_CHARACTERS['0'] = 0x7E
MAX_CHARACTERS['1'] = 0x30
MAX_CHARACTERS['2'] = 0x6D
MAX_CHARACTERS['3'] = 0x79
MAX_CHARACTERS['4'] = 0x33
MAX_CHARACTERS['5'] = 0x5B
MAX_CHARACTERS['6'] = 0x5F
MAX_CHARACTERS['7'] = 0x70
MAX_CHARACTERS['8'] = 0x7F
MAX_CHARACTERS['9'] = 0x7B
MAX_CHARACTERS['-'] = 0x01
MAX_CHARACTERS[' '] = 0x00
MAX_CHARACTERS['A'] = 0x77
MAX_CHARACTERS['B'] = 0x1F
MAX_CHARACTERS['C'] = 0x0D
MAX_CHARACTERS['D'] = 0x3D
MAX_CHARACTERS['E'] = 0x4F
MAX_CHARACTERS['F'] = 0x47
MAX_CHARACTERS['G'] = 0x73
MAX_CHARACTERS['H'] = 0x37
MAX_CHARACTERS['I'] = 0x30
MAX_CHARACTERS['J'] = 0x38
MAX_CHARACTERS['K'] = 0x37
MAX_CHARACTERS['L'] = 0x0E
MAX_CHARACTERS['O'] = 0x7E
MAX_CHARACTERS['P'] = 0x67
MAX_CHARACTERS['S'] = 0x5B
MAX_CHARACTERS['U'] = 0x3E

function setupDisplay()
    spi.setup(1, spi.MASTER, spi.CPOL_LOW, spi.CPHA_LOW, 16, 8)

    sendByte (MAX7219_REG_SHUTDOWN, 1)
    sendByte (MAX7219_REG_SCANLIMIT, 7)
    sendByte (MAX7219_REG_DECODEMODE, 0x00)
    sendByte (MAX7219_REG_DISPLAYTEST, 0)
    sendByte (MAX7219_REG_INTENSITY, 1)
    sendByte (MAX7219_REG_SHUTDOWN, 1)
end

function sendByte(reg, data)
  spi.send(1,reg * 256 + data)
  tmr.delay(50)
end

function doDisplay(text)
    local displayTable = {}
    local key = 0

    for v in string.gmatch(text, ".") do
        if v == '.' then
            displayTable[key] = displayTable[key] + 128
        else 
            key = key + 1
            displayTable[key] = MAX_CHARACTERS[string.upper(v)];
        end
    end

    if key < 8 then 
        for i=key+1,8 do
            displayTable[i] = MAX_CHARACTERS[' '];
        end
    end
    
    for i=1,8 do
        sendByte(i,displayTable[9-i]);
    end
end
function parseApiResponse(apiResponse)
    --print("Parsing the response")
    
    for jsonString in string.gmatch(apiResponse, "{.+}") do
        --print("jsonString found!")
        -- do it this way, because this is normally in miliseconds and overflows
        local currentTime=string.match(apiResponse, 'currentTime":(..........)')
        responseTable = cjson.decode(jsonString)
        
        dataEntriesTable = responseTable['data']['entry'];
        referenceTable = responseTable['data']['references'];

        for k,v in pairs(dataEntriesTable['stopTimes']) do
            if k == 1 then
                arrivalTime = v['predictedArrivalTime'] or v['arrivalTime'];
                
                timeDifference=arrivalTime - currentTime
                diffInMinutes=math.floor(timeDifference / 60)
                diffInSeconds=timeDifference % 60
    
                routeId = referenceTable['trips'][ v['tripId'] ]['routeId'];
                routeName = referenceTable['routes'][routeId]['shortName'];
    
                displayText = string.format('%-4s%02d.%02d', routeName, diffInMinutes, diffInSeconds)
    
                --print(displayText)
                doDisplay(displayText)
            end
        end
    end
end

function getDeparturesFrom(stId)
    print('Getting departures from ' .. stId)
    local apiResponse = ''
    
    conn=net.createConnection(net.TCP, 0)
    conn:on("receive", function(c, data) apiResponse=apiResponse .. data end)
    --conn:on("receive", function(c, payload) print(payload .. "\r\n____\r\n") end)
    conn:on("disconnection", function(sck) 
        parseApiResponse(apiResponse)
        sck:close()
    end)
    conn:on('connection', function(sck)
        print('Connected!')

        --https://github.com/nodemcu/nodemcu-firmware/issues/730#issuecomment-154241161
        local headersToSend = {
            "GET /bkk-utvonaltervezo-api/ws/otp/api/where/arrivals-and-departures-for-stop.json?",
            "includeReferences=trips,routes&stopId=" .. stId .. "&onlyDepartures=false&minutesAfter=30 HTTP/1.1\r\n",
            "Host: futar.bkk.hu\r\n",
            --"Connection: keep-alive\r\n",
            "Connection: close\r\n",
            "Accept-Charset: iso-8859-2",
            "Accept: */*\r\n\r\n",
        }      
        local function sender (sck)
            if #headersToSend > 0 then 
                sck:send(table.remove(headersToSend, 1))
            else 
                print('Pack sent!')
            end
        end
        sck:on("sent", sender)
        sender(sck)
    end)
    net.dns.resolve("futar.bkk.hu", function(sk, ip)
        if (ip == nil) then 
            print("DNS fail!") 
        else 
            conn:connect(80, ip)
        end
    end)
    
end

setupDisplay()
doDisplay("-.-    -.-")

tmr.register(0, 10000, tmr.ALARM_AUTO, function()
    getDeparturesFrom(stopId)
end)

getDeparturesFrom(stopId)
tmr.start(0)
