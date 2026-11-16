-- Digital DTM (DTM Mods): the monitor's settings in multiplayer (picked storage, connected silos, screen
-- size, brightness, colours, title). A client sends them to the server, the server applies them and passes
-- them on to everyone, so all players see the same screen.

StorageMonitorSettingsEvent = {}
local StorageMonitorSettingsEvent_mt = Class(StorageMonitorSettingsEvent, Event)
InitEventClass(StorageMonitorSettingsEvent, "StorageMonitorSettingsEvent")

function StorageMonitorSettingsEvent.emptyNew()
    return Event.new(StorageMonitorSettingsEvent_mt)
end

function StorageMonitorSettingsEvent.new(placeable, settings)
    local self = StorageMonitorSettingsEvent.emptyNew()
    self.placeable = placeable
    self.settings = settings
    return self
end

function StorageMonitorSettingsEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    StorageMonitor.writeSettings(streamId, self.settings)
end

function StorageMonitorSettingsEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.settings = StorageMonitor.readSettings(streamId)
    self:run(connection)
end

function StorageMonitorSettingsEvent:run(connection)
    if self.placeable ~= nil and self.placeable.setStorageMonitorSettings ~= nil then
        self.placeable:setStorageMonitorSettings(self.settings, true)
    end
    if not connection:getIsServer() then
        g_server:broadcastEvent(StorageMonitorSettingsEvent.new(self.placeable, self.settings), nil, connection, self.placeable)
    end
end

function StorageMonitorSettingsEvent.sendEvent(placeable, settings, noEventSend)
    if noEventSend then
        return
    end
    local event = StorageMonitorSettingsEvent.new(placeable, settings)
    if g_server ~= nil then
        g_server:broadcastEvent(event, nil, nil, placeable)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(event)
    end
end

-- The history the server keeps (a sample every half in-game hour): each new sample goes to every player, so the
-- history graph is the same for everyone and survives restarts (it is saved with the game).
StorageMonitorGraphEvent = {}
local StorageMonitorGraphEvent_mt = Class(StorageMonitorGraphEvent, Event)
InitEventClass(StorageMonitorGraphEvent, "StorageMonitorGraphEvent")

function StorageMonitorGraphEvent.emptyNew()
    return Event.new(StorageMonitorGraphEvent_mt)
end

function StorageMonitorGraphEvent.new(placeable, key, sample, reset)
    local self = StorageMonitorGraphEvent.emptyNew()
    self.placeable = placeable
    self.key = key
    self.sample = sample
    self.reset = reset == true
    return self
end

function StorageMonitorGraphEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteString(streamId, self.key or "")
    streamWriteBool(streamId, self.reset)
    StorageMonitor.writeSample(streamId, self.sample)
end

function StorageMonitorGraphEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.key = streamReadString(streamId)
    self.reset = streamReadBool(streamId)
    self.sample = StorageMonitor.readSample(streamId)
    self:run(connection)
end

function StorageMonitorGraphEvent:run(connection)
    if self.placeable ~= nil and self.placeable.spec_storageMonitor ~= nil then
        StorageMonitor.addServerSample(self.placeable, self.key, self.sample, self.reset)
    end
end
