//
//  ViewController.swift
//  Bitcoins
//
//  Created by SukPoet on 2022/10/20.
//

import UIKit
import CoreData

enum CurrencyType: String {
    case usd = "$"
    case gbp = "£"
    case eur = "€"
}

enum BTCURLRequestCustomError: Error {
    case noDataReceived
    case invalidURL
}

class ViewController: UIViewController,UIGestureRecognizerDelegate {
    @IBOutlet weak var usdRateLabel: UILabel!
    @IBOutlet weak var gbpRateLabel: UILabel!
    @IBOutlet weak var eurRateLabel: UILabel!
    
    @IBOutlet weak var subTitleLabel: UILabel!
    @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
    
    @IBOutlet weak var calculateExchangeTextField: UITextField!
    @IBOutlet weak var calculateExchangeLabel: UILabel!
    
    @IBOutlet weak var countDownProgressView: OProgressView!
    
    var currencyType2Calculate = CurrencyType.usd
    let currencyTypes = ["USD","GBP","EUR"]
    
    var thaiDateFormater = DateFormatter()
    var dateFormater = ISO8601DateFormatter()
    
    var appDelegate = UIApplication.shared.delegate as? AppDelegate
    lazy var persistentContainer: NSPersistentContainer? = {
        appDelegate?.persistentContainer
    }()
    //A tap gesture to dimiss keyboard when user tap on screen
    lazy var resignFirstResponderGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tapRecognized(gesture:)))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()
    var updatedRate: Minute?
    var countdownTimer: Timer?
    //Count down every 1 minute to update the data
    var secondsPast = 0
    var timeIsPaused = false
    
    let apiURL = URL(string: "https://api.coindesk.com/v1/bpi/currentprice.json")
    var urlSession: BTCURLSessionMockProtocol = URLSession.shared
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        thaiDateFormater.locale = Locale(identifier: "th-TH");
        thaiDateFormater.dateStyle = .medium
        thaiDateFormater.timeStyle = .medium
        
        NotificationCenter.default.addObserver(self, selector: #selector(pauseTimer), name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeTimer), name: UIScene.didActivateNotification, object: nil)
        
        fetchInitialCurrencyRates()
    }

    func fetchInitialCurrencyRates() {
        // break the strong referece cycle between ViewController and the closure by declaring self as unowned reference in the capture list. Unlike a weak reference, an unowned reference is expected to always have a value. In this context, the ViewController is expected to have a longer life than a single network request.
        request {[unowned self] result in
            DispatchQueue.main.async {[unowned self] in
                activityIndicatorView.stopAnimating()
            } // UI refresh should take place in main thread
            switch result {
            case .success(let minute):
                updatedRate = minute
                if let rateNewest = updatedRate {
                    appDelegate?.saveContext()
                    if let rateTime = rateNewest.time {
                        DispatchQueue.main.async {[unowned self] in
                            subTitleLabel.text = thaiDateFormater.string(from: rateTime)
                            subTitleLabel.isHidden = false
                            usdRateLabel.text = "$ \(rateNewest.usd?.rate ?? "")"
                            gbpRateLabel.text = "£ \(rateNewest.gbp?.rate ?? "")"
                            eurRateLabel.text = "€ \(rateNewest.eur?.rate ?? "")"
                            startTimer()
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {[unowned self] in
                    popUpErrorNotice(error)
                }
            }
        }
    }
    
    func popUpErrorNotice(_ error: Error) {
        let alert = UIAlertController(title: error.localizedDescription, message: "Try to request API again?", preferredStyle: .alert)
        let yesAction = UIAlertAction(title: "YES", style: .default) { [unowned self] _ in //define an unowned self in capture list to break strong reference cycle. The reason to use "unowned" rather than "weak" is that self is expected to have a longer life time, and it won't be nil when the alert is on screen.
            fetchInitialCurrencyRates()
        }
        let noAction = UIAlertAction(title: "NO", style: .cancel)
        alert.addAction(yesAction)
        alert.addAction(noAction)
        present(alert, animated: true)
    }
    
    @objc func refreshProgress() {
        secondsPast += 1
        countDownProgressView.drawCountDownProgress(seconds: secondsPast)
        if secondsPast == 60 {
            request {[unowned self] result in
                DispatchQueue.main.async {[unowned self] in
                    activityIndicatorView.stopAnimating()
                }
                if case .success(let minute) = result {
                    updatedRate = minute
                    if let rateNewest = updatedRate {
                        appDelegate?.saveContext()
                        if let rateTime = rateNewest.time {
                            DispatchQueue.main.async {[unowned self] in
                                secondsPast = 0
                                resumeTimer()
                                subTitleLabel.text = thaiDateFormater.string(from: rateTime)
                                subTitleLabel.isHidden = false
                                usdRateLabel.text = "$ \(rateNewest.usd?.rate ?? "")"
                                gbpRateLabel.text = "£ \(rateNewest.gbp?.rate ?? "")"
                                eurRateLabel.text = "€ \(rateNewest.eur?.rate ?? "")"
                                refreshCalculateResultLabel()
                            }
                        }
                    }
                }
            }
        }
    }
    
    //MARK: refresh currency rates data every 1 minute with a timer. Countdown the time to refresh with a custom progress view
    func startTimer() {
        countdownTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(refreshProgress), userInfo: nil, repeats: true)
        countdownTimer?.tolerance = 0.5 //As the user of the timer, you can determine the appropriate tolerance for a timer. A general rule, set the tolerance to at least 10% of the interval, for a repeating timer. Even a small amount of tolerance has significant positive impact on the power usage of your application.
    }
    // pause the timer when app resigns active
    @objc func pauseTimer() {
        countdownTimer?.fireDate = Date.distantFuture
        timeIsPaused = true
    }
    // resume the timer when app becomes active
    @objc func resumeTimer() {
        if timeIsPaused {
            countdownTimer?.fireDate = Date(timeIntervalSinceNow: 1.0)
            timeIsPaused = false
        }
    }
    
    func request(completion: @escaping (Result<Minute?, Error>) -> Void) {
        activityIndicatorView?.startAnimating()
        activityIndicatorView?.isHidden = false
        
        guard let url = apiURL else {
            completion(.failure(BTCURLRequestCustomError.invalidURL))
            return;
        }
        
        if countdownTimer != nil, updatedRate != nil {
            pauseTimer()
        }
        // This is to demostrate how to use weak reference to break strong reference cycle. Weak reference may become nil at some point in the future, so weak references are always of optional value. In terms of ARC ownership model, an unowned optional reference and a weak reference can both be used in the same context.
        let task = urlSession.dataTask(with: url) { [weak self] (data, response, error) in
            guard error == nil else {
                completion(.failure(error!))
                return
            }
            if data == nil {
                completion(.failure(BTCURLRequestCustomError.noDataReceived))
            } else {
                DispatchQueue.main.async { [weak wself = self] in
                    let minute = wself?.exchangeRateFromJson(fromData: data!)
                    wself?.updatedRate = minute
                    completion(.success(minute))
                }
            }
        }
        task.resume()
    }
    
    //parse data from API into model
    func exchangeRateFromJson(fromData data: Data) -> Minute? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return nil }
        guard let time = json["time"] as? Dictionary<String, String>, let bpi = json["bpi"] as? Dictionary<String,Dictionary<String, Any>>, let managedContext = persistentContainer?.viewContext else { return nil }
        
        let minute = Minute(context: managedContext)
        let updatedISO = time["updatedISO"]
        let timeDate = dateFormater.date(from: updatedISO ?? "")
        minute.timeDescription = updatedISO
        minute.time = timeDate
        
        let usdDict = bpi["USD"];
        let usdCurrency = USDCurrency(context: managedContext)
        usdCurrency.code = usdDict?["code"] as! String?
        usdCurrency.symbol = usdDict?["symbol"] as! String?
        usdCurrency.rate = usdDict?["rate"] as! String?
        usdCurrency.currencyDescription = usdDict?["description"] as! String?
        let usdRateNumber = usdDict?["rate_float"] as! NSNumber
        usdCurrency.rate_float = usdRateNumber.doubleValue
        minute.usd = usdCurrency
        
        let gbpDict = bpi["GBP"];
        let gbpCurrency = GBPCurrency(context: managedContext)
        gbpCurrency.code = gbpDict?["code"] as! String?
        gbpCurrency.symbol = gbpDict?["symbol"] as! String?
        gbpCurrency.rate = gbpDict?["rate"] as! String?
        gbpCurrency.currencyDescription = gbpDict?["description"] as! String?
        let gbpRateNumber = gbpDict?["rate_float"] as! NSNumber
        gbpCurrency.rate_float = gbpRateNumber.doubleValue
        minute.gbp = gbpCurrency
        
        let eurDict = bpi["EUR"];
        let eurCurrency = EURCurrency(context: managedContext)
        eurCurrency.code = eurDict?["code"] as! String?
        eurCurrency.symbol = eurDict?["symbol"] as! String?
        eurCurrency.rate = eurDict?["rate"] as! String?
        eurCurrency.currencyDescription = eurDict?["description"] as! String?
        let eurRateNumber = eurDict?["rate_float"] as! NSNumber
        eurCurrency.rate_float = eurRateNumber.doubleValue
        minute.eur = eurCurrency
        
        return minute
    }
    
    func refreshCalculateResultLabel() {
        if let text = calculateExchangeTextField.text, let btc = Double(text), let rates = updatedRate {
            var exchangeRate = Double()
            switch currencyType2Calculate {
            case .usd:
                if let rate = rates.usd?.rate_float {
                    exchangeRate = rate
                }
            case .gbp:
                if let rate = rates.gbp?.rate_float {
                    exchangeRate = rate
                }
            case .eur:
                if let rate = rates.eur?.rate_float {
                    exchangeRate = rate
                }
            }
            calculateExchangeLabel.text = currencyType2Calculate.rawValue + " " + String(format: "%.2f", btc*exchangeRate)
        } else {
            calculateExchangeLabel.text = "   "
        }
    }
    
    @objc func tapRecognized(gesture: UITapGestureRecognizer) {
        if calculateExchangeTextField.isFirstResponder && gesture.state == .ended {
            calculateExchangeTextField.resignFirstResponder()
        }
    }
    //MARK: UIGestureRecognizerDelegate
    /** Note: returning YES is guaranteed to allow simultaneous recognition. returning NO is not guaranteed to prevent simultaneous recognition, as the other gesture's delegate may return YES. */
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    /** To not detect touch events in a subclass of UIControl, these may have added their own selector for specific work */
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let touchedView = touch.view, (touchedView is UIControl || touchedView is UINavigationBar) {
            return false
        }
        return true
    }
}

extension ViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    //MARK: UIPickerViewDataSource
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return 3
    }
    
    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        let text = currencyTypes[row]
        return NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 15.0)])
    }
    //MARK: UIPickerViewDelegate
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch row {
        case 0:
            currencyType2Calculate = .usd
        case 1:
            currencyType2Calculate = .gbp
        case 2:
            currencyType2Calculate = .eur
        default:
            currencyType2Calculate = .usd
        }
        
        refreshCalculateResultLabel()
    }
}

//MARK: UITextFieldDelegate
extension ViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.window?.addGestureRecognizer(resignFirstResponderGesture)
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.window?.removeGestureRecognizer(resignFirstResponderGesture)
        if let text = textField.text, let btc = Double(text), let rates = updatedRate {
            var exchangeRate = Double()
            switch currencyType2Calculate {
            case .usd:
                if let rate = rates.usd?.rate_float {
                    exchangeRate = rate
                }
            case .gbp:
                if let rate = rates.gbp?.rate_float {
                    exchangeRate = rate
                }
            case .eur:
                if let rate = rates.eur?.rate_float {
                    exchangeRate = rate
                }
            }
            calculateExchangeLabel.text = currencyType2Calculate.rawValue + " " + String(format: "%.2f", btc*exchangeRate)
        } else {
            calculateExchangeLabel.text = "   "
        }
    }
    
    // make sure the input text is always of the corret dicimal format by evaluating it with regulare expresion. "000...67.0.3" "002.7.0.3" are not valid decimal numbers.
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        var text = textField.text ?? ""
        if string.isEmpty {
            if text.isEmpty {
                return true
            } else {
                let startIndex = text.startIndex
                let rangeIndex1 = text.index(startIndex, offsetBy: range.location)
                let rangeIndex2 = text.index(rangeIndex1, offsetBy: range.length)
                let range2Remove = rangeIndex1..<rangeIndex2
                text.removeSubrange(range2Remove)
            }
        } else {
            if range.length == 0 && range.location == text.count {
                text += string
            } else {
                let startIndex = text.startIndex
                let rangeIndex1 = text.index(startIndex, offsetBy: range.location)
                let pre = text.prefix(upTo: rangeIndex1)
                let rear = text.suffix(from: rangeIndex1)
                text = String(pre) + string + String(rear)
            }
        }
        if text.isEmpty {
            return true
        }
        let predicate0 = NSPredicate(format: "SELF MATCHES %@", "^[0][0-9]+$")
        let predicate1 = NSPredicate(format: "SELF MATCHES %@", "^(([1-9]{1}[0-9]*|[0])\\.?[0-9]{0,8})$")
        let pass = (!predicate0.evaluate(with: text) && predicate1.evaluate(with: text)) ? true : false
        return pass
    }
    
}
