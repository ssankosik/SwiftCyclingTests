import Foundation

/**
 Not leak:
 
 - Non-escaping:
 ```
    // UIView.animate
    UIView.animate(
        withDuration: 3.0,
        delay: 3.0,
        animations: {
            self.view.backgroundColor = .blue
        },
        completion: { _ in
            self.view.backgroundColor = .green
        })
 
    // Higher order function
    let numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    numbers.forEach({ self.view.tag = $0 })
    numbers.filter({ $0 == self.view.tag })
 
    // Other
    func run(closure: () -> Void) {
        closure()
    }
     
    run {
        self.view.backgroundColor = .red
    }
 ```
 Non-escaping closure (executes immediately), no need [weak self].
 
 - execute a Dispatch closure immediately without storing it:
 ```
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self.view.backgroundColor = .red
    }
     
    DispatchQueue.main.async {
        self.view.backgroundColor = .red
    }
     
    DispatchQueue.global(qos: .background).async {
        print(self.navigationItem.description)
    }
 ```
 Execute a Dispatch closure immediately without storing it, no need [weak self].
 */

/**
 Leak:
 
 - Store a Dispatch closure:
 ```
    let workItem = DispatchWorkItem { self.view.backgroundColor = .red }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    self.closureStorage = workItem
 ```
 Store a Dispatch closure, it escapes, will leak [weak self] needed.
 
 - @escaping without [weak self]:
 ```
    func run(closure: @escaping () -> Void) {
        closure()
        self.closureStorage = closure
    }
     
    run {
        self.view.backgroundColor = .red
    }
 ```
 Closure and 'self' reference each other, will leak [weak self] needed.
 
 - Nested closure:
 ```
    let workItem = DispatchWorkItem {
        UIView.animate(withDuration: 1.0) { [weak self] in
            self?.view.backgroundColor = .red
        }
    }
 
    self.closureStorage = workItem
    DispatchQueue.main.async(execute: workItem)
 ```
 Work Item creates a strong reference, will leak [weak self] needed.
 */

fileprivate class Publisher {
    var accept: (() -> Void)?
    
    func execute(completion: (() -> Void)?) {
        self.accept = completion
    }
}

fileprivate protocol ModelProtocol: AnyObject {
    var id: String { get }
    var aPublisher: Publisher { get }
    var bPublisher: Publisher { get }
    var cPublisher: Publisher { get }
    func log(id newId: String)
    func publishAll()
    func executeStrongSelf()
    func executeSingleGuard()
    func executeGuardAll()
    func executeWeakSelf()
    func executeNestedFunction()
}

extension ModelProtocol {
    func publishAll() {
        aPublisher.accept?()
        bPublisher.accept?()
        cPublisher.accept?()
    }
    
    func executeStrongSelf() {
        aPublisher.execute(completion: {
            self.bPublisher.execute(completion: {
                self.cPublisher.execute(completion: {
                    self.log(id: "Strong self")
                })
            })
        })
    }
    
    func executeSingleGuard() {
        aPublisher.execute(completion: { [weak self] in
            guard let self = self else { return }
            self.bPublisher.execute(completion: {
                self.cPublisher.execute(completion: {
                    self.log(id: "Single guard")
                })
            })
        })
    }
    
    func executeGuardAll() {
        aPublisher.execute(completion: { [weak self] in
            guard let self = self else { return }
            self.bPublisher.execute(completion: { [weak self] in
                guard let self = self else { return }
                self.cPublisher.execute(completion: { [weak self] in
                    guard let self = self else { return }
                    self.log(id: "Guard all")
                })
            })
        })
    }
    
    func executeWeakSelf() {
        aPublisher.execute(completion: { [weak self] in
            self?.bPublisher.execute(completion: {
                self?.cPublisher.execute(completion: {
                    self?.log(id: "Weak self")
                })
            })
        })
    }
    
    func executeNestedFunction() {
        func nestedLog() {
            log(id: "Nested function")
        }
        
        aPublisher.execute(completion: { [weak self] in
            self?.bPublisher.execute(completion: {
                self?.cPublisher.execute(completion: {
                    guard let self = self else { return }
                    nestedLog()
                })
            })
        })
    }
}

fileprivate class Model:
    ModelProtocol
{
    let id: String
    let aPublisher = Publisher()
    let bPublisher = Publisher()
    let cPublisher = Publisher()
    
    init(id: String) {
        self.id = id
    }
    
    deinit {
        print("\(id) deinit")
    }
    
    func log(id newId: String) {
        print("\(id) received \(newId)")
    }
}

class CyclingTests {
    private static var aModel: ModelProtocol? = Model(id: "A")
    private static var bModel: ModelProtocol? = Model(id: "B")
    private static var cModel: ModelProtocol? = Model(id: "C")
    private static var dModel: ModelProtocol? = Model(id: "D")
    private static var eModel: ModelProtocol? = Model(id: "E")
    
    static func tests() {
        test()
    }
    
    /**
     Result:
     ```
     [When]:
     A received Strong self
     B received Single guard
     C received Guard all
     D received Weak self
     E received Nested function
     [Then]:
     C deinit
     D deinit
     ```
     */
    static func test() {
        // Given
        aModel?.executeStrongSelf()
        bModel?.executeSingleGuard()
        cModel?.executeGuardAll()
        dModel?.executeWeakSelf()
        eModel?.executeNestedFunction()
        
        print("[When]:")
        aModel?.publishAll()
        bModel?.publishAll()
        cModel?.publishAll()
        dModel?.publishAll()
        eModel?.publishAll()
        
        print("[Then]:")
        aModel = nil
        bModel = nil
        cModel = nil
        dModel = nil
        eModel = nil
    }
}
