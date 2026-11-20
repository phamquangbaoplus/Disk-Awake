import Foundation
import DiskArbitration

// Disk Arbitration also reports unmounted volumes, unlike mountedVolumeURLs.
@MainActor
final class ExternalVolumeManager {
    private let session: DASession?
    private var volumes: [String: DADisk] = [:]
    private var inFlight: [String: Bool] = [:]
    private var desiredMounted: Bool?

    init() {
        session = DASessionCreate(kCFAllocatorDefault)
        guard let session else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, { disk, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<ExternalVolumeManager>.fromOpaque(context).takeUnretainedValue().appeared(disk)
            }
        }, context)
        // Filesystem details can become available after the initial appearance.
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { disk, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<ExternalVolumeManager>.fromOpaque(context).takeUnretainedValue().appeared(disk)
            }
        }, context)
        DARegisterDiskDisappearedCallback(session, nil, { disk, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let manager = Unmanaged<ExternalVolumeManager>.fromOpaque(context).takeUnretainedValue()
                if let name = DADiskGetBSDName(disk) {
                    manager.volumes.removeValue(forKey: String(cString: name))
                }
            }
        }, context)
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    func setMounted(_ mounted: Bool) {
        guard desiredMounted != mounted else { return }
        desiredMounted = mounted
        for disk in volumes.values { reconcile(disk) }
    }

    private func appeared(_ disk: DADisk) {
        guard let name = DADiskGetBSDName(disk),
              let description = DADiskCopyDescription(disk) as? [String: Any],
              description[kDADiskDescriptionDeviceInternalKey as String] as? Bool == false,
              description[kDADiskDescriptionVolumeMountableKey as String] as? Bool == true,
              description[kDADiskDescriptionVolumeKindKey as String] != nil else { return }
        volumes[String(cString: name)] = disk
        reconcile(disk)
    }

    private func reconcile(_ disk: DADisk) {
        guard let desiredMounted, let session, let name = DADiskGetBSDName(disk),
              let currentDisk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, name),
              let description = DADiskCopyDescription(currentDisk) as? [String: Any] else { return }
        let id = String(cString: name)
        let mounted = description[kDADiskDescriptionVolumePathKey as String] != nil
        guard mounted != desiredMounted, inFlight[id] == nil else { return }
        inFlight[id] = desiredMounted
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: DADiskMountCallback = { disk, dissenter, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let manager = Unmanaged<ExternalVolumeManager>.fromOpaque(context).takeUnretainedValue()
                guard let name = DADiskGetBSDName(disk) else { return }
                let id = String(cString: name)
                let requestedMount = manager.inFlight.removeValue(forKey: id)
                if let dissenter {
                    NSLog("Disk Awake: volume operation failed: %@", DADissenterGetStatusString(dissenter) as String? ?? "unknown error")
                }
                // Apply a newer policy even when the previous operation failed.
                // Do not retry a failed operation indefinitely.
                if let requestedMount, requestedMount != manager.desiredMounted,
                   let current = manager.volumes[id] {
                    manager.reconcile(current)
                }
            }
        }
        if desiredMounted {
            DADiskMount(currentDisk, nil, DADiskMountOptions(kDADiskMountOptionDefault), callback, context)
        } else {
            DADiskUnmount(currentDisk, DADiskUnmountOptions(kDADiskUnmountOptionDefault), callback, context)
        }
    }
}
