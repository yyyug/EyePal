import CoreMotion
import CoreLocation
import Combine

/// Protocol for user head tracking
protocol UserHeadingProvider: AnyObject {
    var accuracy: Double { get }
    var delegate: UserHeadingProviderDelegate? { get set }
    func startUserHeadingUpdates()
    func stopUserHeadingUpdates()
}

/// Delegate for head tracking updates
protocol UserHeadingProviderDelegate: AnyObject {
    func userHeadingProvider(_ provider: UserHeadingProvider, didUpdateUserHeading heading: HeadingValue?)
}

/// Head tracking data value
struct HeadingValue: Equatable {
    let value: Double      // Heading in degrees
    let accuracy: Double?  // Accuracy estimate
    
    init(_ value: Double, _ accuracy: Double? = nil) {
        self.value = value
        self.accuracy = accuracy
    }
}

/// Provides user head orientation from headphones with motion sensors (iOS 14.4+)
@available(iOS 14.4, *)
final class HeadphoneMotionProvider: NSObject, UserHeadingProvider, ObservableObject {
    // MARK: - Properties
    private let manager = CMHeadphoneMotionManager()
    private let motionQueue = OperationQueue()
    private var lastYaw: Double = 0.0
    
    @Published var currentHeading: HeadingValue?
    
    weak var delegate: UserHeadingProviderDelegate?
    
    var accuracy: Double = 0.0 {
        didSet {
            print("📍 Headphone motion accuracy: \(accuracy)°")
        }
    }
    
    var isHeadphoneMotionAvailable: Bool {
        manager.isDeviceMotionAvailable
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        motionQueue.maxConcurrentOperationCount = 1
        print("✅ HeadphoneMotionProvider initialized (iOS 14.4+)")
    }
    
    // MARK: - Head Tracking Control
    func startUserHeadingUpdates() {
        guard isHeadphoneMotionAvailable else {
            print("⚠️ Headphone motion not available on this device")
            return
        }
        
        manager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self else { return }
            
            if let error {
                print("❌ Headphone motion error: \(error)")
                return
            }
            
            guard let motion else { return }
            
            // Extract yaw (heading) from device attitude
            let yawDegrees = motion.attitude.yaw.radiansToDegrees
            let normalizedYaw = self.normalizeHeading(yawDegrees)
            
            // Update heading with accuracy estimate
            let headingValue = HeadingValue(normalizedYaw, 5.0) // 5 degree accuracy
            
            DispatchQueue.main.async {
                self.lastYaw = normalizedYaw
                self.delegate?.userHeadingProvider(self, didUpdateUserHeading: headingValue)
            }
        }
        
        print("▶️ Head motion updates started")
    }
    
    func stopUserHeadingUpdates() {
        manager.stopDeviceMotionUpdates()
        print("⏹️ Head motion updates stopped")
    }
    
    // MARK: - Heading Normalization
    private func normalizeHeading(_ heading: Double) -> Double {
        var normalized = heading.truncatingRemainder(dividingBy: 360.0)
        if normalized < 0 {
            normalized += 360.0
        }
        return normalized
    }
    
    deinit {
        stopUserHeadingUpdates()
    }
}

/// Fallback device heading provider using device compass + motion
final class DeviceMotionProvider: NSObject, UserHeadingProvider, ObservableObject {
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let operationQueue = OperationQueue()
    
    @Published var currentHeading: HeadingValue?
    
    weak var delegate: UserHeadingProviderDelegate?
    
    var accuracy: Double = 0.0
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUserHeadingUpdates() {
        locationManager.startUpdatingHeading()
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.05
            motionManager.startDeviceMotionUpdates(to: operationQueue) { [weak self] motion, _ in
                guard let motion else { return }
                
                let yawDegrees = motion.attitude.yaw.radiansToDegrees
                let heading = HeadingValue(self?.normalizeHeading(yawDegrees) ?? 0, nil)
                
                DispatchQueue.main.async {
                    self?.delegate?.userHeadingProvider(self!, didUpdateUserHeading: heading)
                }
            }
        }
    }
    
    func stopUserHeadingUpdates() {
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()
    }
    
    private func normalizeHeading(_ heading: Double) -> Double {
        var normalized = heading.truncatingRemainder(dividingBy: 360.0)
        if normalized < 0 {
            normalized += 360.0
        }
        return normalized
    }
}

// MARK: - CLLocationManager Delegate
extension DeviceMotionProvider: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = HeadingValue(newHeading.trueHeading, newHeading.headingAccuracy)
        delegate?.userHeadingProvider(self, didUpdateUserHeading: heading)
    }
}

// MARK: - Angle Conversion
extension Double {
    var radiansToDegrees: Double {
        self * 180.0 / .pi
    }
    
    var degreesToRadians: Double {
        self * .pi / 180.0
    }
}
