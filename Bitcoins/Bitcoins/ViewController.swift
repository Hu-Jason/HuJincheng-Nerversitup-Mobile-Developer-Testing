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

class ViewController: UIViewController,UIGestureRecognizerDelegate {
    @IBOutlet weak var usdRateLabel: UILabel!
    @IBOutlet weak var gbpRateLabel: UILabel!
    @IBOutlet weak var eurRateLabel: UILabel!
    
    @IBOutlet var pageTitleStackView: UIStackView!
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
    lazy var resignFirstResponderGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tapRecognized(gesture:)))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()
    var updatedRate: Minute?
    var countdownTimer: Timer?
    var secondsPast = 0
    var timeIsPaused = false
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        navigationItem.titleView = self.pageTitleStackView;
        thaiDateFormater.locale = Locale(identifier: "th-TH");
        thaiDateFormater.dateStyle = .medium
        thaiDateFormater.timeStyle = .medium
        
        NotificationCenter.default.addObserver(self, selector: #selector(pauseTimer), name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeTimer), name: UIScene.didActivateNotification, object: nil)
        
        request {[unowned self] result in
            DispatchQueue.main.async {[unowned self] in
                activityIndicatorView.stopAnimating()
            }
            if case .success(let success) = result {
                updatedRate = success
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
            }
        }
    }

    func startTimer() {
        countdownTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(refreshProgress), userInfo: nil, repeats: true)
    }
    
    @objc func refreshProgress() {
        secondsPast += 1
        countDownProgressView.drawCountDownProgress(seconds: secondsPast)
        if secondsPast == 60 {
            request {[unowned self] result in
                DispatchQueue.main.async {[unowned self] in
                    activityIndicatorView.stopAnimating()
                }
                if case .success(let success) = result {
                    updatedRate = success
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
    
    @objc func pauseTimer() {
        countdownTimer?.fireDate = Date.distantFuture // pause the timer
        timeIsPaused = true
    }
    
    @objc func resumeTimer() {
        if timeIsPaused {
            countdownTimer?.fireDate = Date(timeIntervalSinceNow: 1.0)
            timeIsPaused = false
        }
    }
    
    func request(completion: @escaping (Result<Minute?, Error>) -> Void) {
        activityIndicatorView.startAnimating()
        activityIndicatorView.isHidden = false
        guard let url = URL(string: "https://api.coindesk.com/v1/bpi/currentprice.json") else {
            completion(.success(nil))
            return;
        }
        
        if countdownTimer != nil, updatedRate != nil {
            pauseTimer()
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak weakself = self] (data, response, error) in
            guard error == nil else {
                completion(.failure(error!))
                return
            }
            if data == nil {
                completion(.success(nil))
            } else {
                let minute = weakself?.exchangeRateFromJson(fromData: data!)
                completion(.success(minute))
            }
        }
        task.resume()
    }
    
    func exchangeRateFromJson(fromData data: Data) -> Minute? {
        let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
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
        usdCurrency.rate_float = usdRateNumber.floatValue
        minute.usd = usdCurrency
        
        let gbpDict = bpi["GBP"];
        let gbpCurrency = GBPCurrency(context: managedContext)
        gbpCurrency.code = gbpDict?["code"] as! String?
        gbpCurrency.symbol = gbpDict?["symbol"] as! String?
        gbpCurrency.rate = gbpDict?["rate"] as! String?
        gbpCurrency.currencyDescription = gbpDict?["description"] as! String?
        let gbpRateNumber = gbpDict?["rate_float"] as! NSNumber
        gbpCurrency.rate_float = gbpRateNumber.floatValue
        minute.gbp = gbpCurrency
        
        let eurDict = bpi["EUR"];
        let eurCurrency = EURCurrency(context: managedContext)
        eurCurrency.code = eurDict?["code"] as! String?
        eurCurrency.symbol = eurDict?["symbol"] as! String?
        eurCurrency.rate = eurDict?["rate"] as! String?
        eurCurrency.currencyDescription = eurDict?["description"] as! String?
        let eurRateNumber = eurDict?["rate_float"] as! NSNumber
        eurCurrency.rate_float = eurRateNumber.floatValue
        minute.eur = eurCurrency
        
        return minute
    }
    
    func refreshCalculateResultLabel() {
        if let text = calculateExchangeTextField.text, let btc = Float(text), let rates = updatedRate {
            var exchangeRate = Float()
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
            self.calculateExchangeLabel.text = currencyType2Calculate.rawValue + " " + String(btc*exchangeRate)
        } else {
            self.calculateExchangeLabel.text = ""
        }
    }
    
    @objc func tapRecognized(gesture: UITapGestureRecognizer) {
        if self.calculateExchangeTextField.isFirstResponder && gesture.state == .ended {
            self.calculateExchangeTextField.resignFirstResponder()
        }
    }
    //MARK: UIGestureRecognizerDelegate
    /** Note: returning YES is guaranteed to allow simultaneous recognition. returning NO is not guaranteed to prevent simultaneous recognition, as the other gesture's delegate may return YES. */
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    /** To not detect touch events in a subclass of UIControl, these may have added their own selector for specific work */
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let touchedView = touch.view, (touchedView.isKind(of: UIControl.self) || touchedView.isKind(of: UINavigationBar.self)) {
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
        if let text = textField.text, let btc = Float(text), let rates = updatedRate {
            var exchangeRate = Float()
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
            self.calculateExchangeLabel.text = currencyType2Calculate.rawValue + " " + String(btc*exchangeRate)
        } else {
            self.calculateExchangeLabel.text = ""
        }
    }
    
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