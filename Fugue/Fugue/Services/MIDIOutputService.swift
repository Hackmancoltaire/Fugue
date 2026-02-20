import CoreMIDI
import Foundation
import Observation

struct MIDIDestination: Identifiable, Hashable {
    let name: String
    let endpointRef: MIDIEndpointRef

    var id: String { name }
}

@Observable
class MIDIOutputService {
    var availableDestinations: [MIDIDestination] = []
    var selectedDestinationName: String? {
        didSet {
            UserDefaults.standard.set(selectedDestinationName, forKey: "midiOutputDestination")
            resolveEndpoint()
        }
    }
    private(set) var activeEndpoint: MIDIEndpointRef = 0

    var onEndpointChanged: (() -> Void)?

    var isExternalOutput: Bool { activeEndpoint != 0 }

    private var midiClient = MIDIClientRef()
    private var outputPort = MIDIPortRef()

    init() {
        selectedDestinationName = UserDefaults.standard.string(forKey: "midiOutputDestination")

        // Enable the CoreMIDI network session so network destinations appear alongside
        // hardware/virtual ports in MIDIGetNumberOfDestinations(). Disabled by default per-process.
        let networkSession = MIDINetworkSession.default()
        networkSession.isEnabled = true
        networkSession.connectionPolicy = .anyone

        MIDIClientCreateWithBlock("Fugue" as CFString, &midiClient) { [weak self] notification in
            let messageID = notification.pointee.messageID
            guard messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async {
                self?.refreshDestinations()
            }
        }

        MIDIOutputPortCreate(midiClient, "Fugue Output" as CFString, &outputPort)

        refreshDestinations()
    }

    func refreshDestinations() {
        var destinations: [MIDIDestination] = []
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let endpoint = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            if let cfName = name?.takeRetainedValue() {
                destinations.append(MIDIDestination(name: cfName as String, endpointRef: endpoint))
            }
        }
        availableDestinations = destinations
        resolveEndpoint()
    }

    func sendMIDIEvent(status: UInt8, data1: UInt8, data2: UInt8) {
        guard activeEndpoint != 0 else { return }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        let midiData: [UInt8] = [status, data1, data2]
        packet = MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size, packet, 0, 3, midiData)
        MIDISend(outputPort, activeEndpoint, &packetList)
    }

    private func resolveEndpoint() {
        let previousEndpoint = activeEndpoint

        if let name = selectedDestinationName,
           let dest = availableDestinations.first(where: { $0.name == name }) {
            activeEndpoint = dest.endpointRef
        } else {
            activeEndpoint = 0
        }

        if activeEndpoint != previousEndpoint {
            onEndpointChanged?()
        }
    }
}
