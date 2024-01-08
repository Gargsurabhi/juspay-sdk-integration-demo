//
//  CheckoutViewController.swift
//  juspay-sdk-integration-swift
//
//  Created by Arbinda Kumar Prasad on 08/06/23.
//

import UIKit
import HyperSDK

var totalpayable = 1;
var ordeId: String? = nil;
var message: String? = nil;

class CheckoutViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    // block:start:fetch-process-payload
    func getProcessPayload(completion: @escaping ([AnyHashable: Any]?) -> Void) {
        // Make an API Call to your server to create Session and return SDK Payload
        // API Call should be made on the merchants server
        createOrder { jsonData in
            completion(jsonData)
        }
    }
    // block:end:fetch-process-payload

    
    
    
    @IBAction func startPayments(_ sender: Any) {
        getProcessPayload { sdkProcessPayload in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if (sdkProcessPayload != nil){
                    HyperCheckoutLite.openPaymentPage(self, payload: sdkProcessPayload!, callback: hyperCallbackHandler)
                }else{
                    // handle case when sdkProcessPayload is nils
                }
            }
        }
    }
    
    func hyperCallbackHandler(response: [String: Any]?) {
        if let data = response, let event = data["event"] as? String {
            if event == "hide_loader" {
                // hide loader
            }
            // Handle Process Result
            // This case will reach once the Hypercheckout screen closes
            // block:start:handle-process-result
            else if event == "process_result" {
                let error = data["error"] as? Bool ?? false
                
                if let innerPayload = data["payload"] as? [String: Any] {
                    let status = innerPayload["status"] as? String
                    if !error {
                        performSegue(withIdentifier: "statusSegue", sender: status)
                        // txn success, status should be "charged"
                        // process data -- show pi and pig in UI maybe also?
                        // example -- pi: "PAYTM", pig: "WALLET"
                        // call orderStatus once to verify (false positives)
                    } else {
                        switch status != nil ? status : "status not present" {
                        case "backpressed":
                            // user back-pressed from PP without initiating any txn
                            let alertController = UIAlertController(title: "Payment Cancelled", message: "User clicked back button on Payment Page", preferredStyle: .alert)
                            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                            alertController.addAction(okAction)
                            present(alertController, animated: true, completion: nil)

                            break
                        case "user_aborted":
                            // user initiated a txn and pressed back
                            // poll order status
                            callOrderStatus { order_status in
                                let alertController = UIAlertController(title: "Payment Aborted", message: "Transaction aborted by user", preferredStyle: .alert)
                                let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                                alertController.addAction(okAction)
                                self.present(alertController, animated: true, completion: nil)
                            }
                            break
                        case "pending_vbv", "authorizing":
                            // txn in pending state
                            // poll order status until backend says fail or success
                            callOrderStatus { order_status in
                                self.performSegue(withIdentifier: "statusSegue", sender: order_status)
                            }
                            break
                        case "authorization_failed", "authentication_failed", "api_failure":
                            // txn failed
                            // poll orderStatus to verify (false negatives)
                            callOrderStatus { order_status in
                                self.performSegue(withIdentifier: "statusSegue", sender: order_status)
                            }
                            break
                        case "new":
                            // order created but txn failed
                            // very rare for V2 (signature based)
                            // also failure
                            // poll order status
                            callOrderStatus { order_status in
                                self.performSegue(withIdentifier: "statusSegue", sender: order_status)
                            }
                            break
                        default:
                            performSegue(withIdentifier: "statusSegue", sender: status)
                            // unknown status, this is also failure
                            // poll order status
                            break
                        }
                    }
                }
            }
            // block:end:handle-process-result
        }
    }

    func callOrderStatus(completion: @escaping (String?) -> Void) {
        if let order_id = ordeId {
            let semaphore = DispatchSemaphore(value: 0)
            let endpoint = "http://127.0.0.1:5000/handleJuspayResponse?order_id=" + order_id;
            var request = URLRequest(url: URL(string: endpoint)!, timeoutInterval: Double.infinity)
            
            request.httpMethod = "GET"
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data else {
                    semaphore.signal()
                    completion(nil)
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let order_status = json["order_status"] as? String{
                        let msg = json["message"] as? String;
                        message = msg;
                        completion(order_status)
                    } else {
                        completion(nil)
                    }
                } catch {
                    print("Error: Failed to parse JSON - \(error)")
                    completion(nil)
                }
                
                semaphore.signal()
            }
            
            task.resume()
            semaphore.wait()
        }else{
            completion(nil)
        }
    }

    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "statusSegue" {
            if let destinationVC = segue.destination as? StatusViewController {
                if let txnStatus = sender as? String {
                    print(txnStatus)
                    destinationVC.txnStatus = txnStatus
                }
            }
            if let txnStatus = sender as? String {
                print(txnStatus)
            }
        }
    }
    
    func createOrder(completion: @escaping ([String: Any]?) -> Void) {
            let semaphore = DispatchSemaphore(value: 0)
            let endpoint = "http://127.0.0.1:5000/initiateJuspayPayment";
            var request = URLRequest(url: URL(string: endpoint)!, timeoutInterval: Double.infinity)

            request.httpMethod = "POST"
        
            let body: [String: Any] = ["item_details": [["item_id" : "12345", "quantity" : 2], ["item_id" : "54321", "quantity" : 2]]]
            let finalBody = try? JSONSerialization.data(withJSONObject: body)
            request.httpBody = finalBody

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data else {
                    semaphore.signal()
                    completion(nil)
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                        let sdkPayload = json["sdkPayload"] as? [String: Any] {
                        completion(sdkPayload)
                    } else {
                        completion(nil)
                    }
                } catch {
                    print("Error: Failed to parse JSON - \(error)")
                    completion(nil)
                }

                semaphore.signal()
            }

            task.resume()
            semaphore.wait()
        }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
     
     */
    @IBOutlet weak var p1QntyOutlet: UILabel!
    @IBOutlet weak var totalAmount: UILabel!
    @IBOutlet weak var totalPayableOutlet: UILabel!
    @IBOutlet weak var taxOutlet: UILabel!
    @IBOutlet weak var p2Amount: UILabel!
    @IBOutlet weak var p1Amount: UILabel!
    @IBOutlet weak var p2QntyOutlet: UILabel!
}
