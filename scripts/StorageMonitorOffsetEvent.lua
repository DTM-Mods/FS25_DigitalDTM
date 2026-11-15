-- Storage Monitor (DTM Mods): "switch storage" in multiplayer. A client sends the new choice to the
-- server, the server applies it and passes it on to everyone, so all players see the same storage.

StorageMonitorOffsetEvent = {}
local StorageMonitorOffsetEvent_mt = Class(StorageMonitorOffsetEvent, Event)
InitEventClass(StorageMonitorOffsetEvent, "StorageMonitorOffsetEvent")

function StorageMonitorOffsetEvent.emptyNew()
    return Event.new(StorageMonitorOffsetEvent_mt)
end

function StorageMonitorOffsetEvent.new(placeable, offset)
    local self = StorageMonitorOffsetEvent.emptyNew()
    self.placeable = placeable
    self.offset = offset
    return self
end

function StorageMonitorOffsetEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUInt8(streamId, self.offset)
end

function StorageMonitorOffsetEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.offset = streamReadUInt8(streamId)
    self:run(connection)
end

function StorageMonitorOffsetEvent:run(connection)
    if self.placeable ~= nil and self.placeable.setStorageMonitorOffset ~= nil then
        self.placeable:setStorageMonitorOffset(self.offset, true)
    end
    if not connection:getIsServer() then
        g_server:broadcastEvent(StorageMonitorOffsetEvent.new(self.placeable, self.offset), nil, connection, self.placeable)
    end
end

function StorageMonitorOffsetEvent.sendEvent(placeable, offset, noEventSend)
    if noEventSend then
        return
    end
    if g_server ~= nil then
        g_server:broadcastEvent(StorageMonitorOffsetEvent.new(placeable, offset), nil, nil, placeable)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(StorageMonitorOffsetEvent.new(placeable, offset))
    end
end
