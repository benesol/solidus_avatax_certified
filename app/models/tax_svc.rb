require 'active_record'
require 'json'
require 'net/http'
require 'addressable/uri'
require 'base64'
require 'rest-client'
require 'logging'

# Avatax tax calculation API calls
class TaxSvc
  def get_tax(request_hash)
    log(__method__, request_hash)
    RestClient.log = logger.logger
    res = response('get', request_hash)
    logger.info_and_debug('RestClient call', res)

    if res['ResultCode'] != 'Success'
      logger.info 'Avatax Error'
      logger.debug res, 'error in Tax'
      raise 'error in Tax'
    else
      res
    end
  rescue => e
    logger.info 'Rest Client Error'
    logger.debug e, 'error in Tax'
    'error in Tax'
  end

  def cancel_tax(request_hash)
    log(__method__, request_hash)
    res = response('cancel', request_hash)['CancelTaxResult']
    logger.debug res

    if res['ResultCode'] != 'Success'
      logger.info_and_debug("Avatax Error: Order ##{res['Messages'][0]['Details']}", res)
    end

    res
  rescue => e
    logger.debug e, 'Error in Cancel Tax'
    'Error in Cancel Tax'
  end

  def estimate_tax(coordinates, sale_amount)
    prefs = Spree::AvalaraPreference.get_all_preferences
    if tax_calculation_enabled(prefs) == true
      log(__method__)

      return nil if coordinates.nil?
      sale_amount = 0 if sale_amount.nil?
      coor = coordinates[:latitude].to_s + ',' + coordinates[:longitude].to_s

      uri = URI(service_url(prefs) + coor + '/get?saleamount=' + sale_amount.to_s)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      res = http.get(uri.request_uri, 'Authorization' => credential(prefs), 'Content-Type' => 'application/json')
      JSON.parse(res.body)
    end
  rescue => e
    logger.debug e, 'error in Estimate Tax'
    'error in Estimate Tax'
  end

  def ping
    logger.info 'Ping Call'
    estimate_tax({ latitude: '40.714623', longitude: '-74.006605' }, 0)
  end

  def validate_address(address)
    prefs = Spree::AvalaraPreference.get_all_preferences
    uri = URI(address_service_url(prefs) + address.to_query)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    res = http.get(uri.request_uri, 'Authorization' => credential(prefs))

    logger.debug res

    JSON.parse(res.body)
  rescue => e
    "error in address validation: #{e}"
  end

  protected

  def logger
    SolidusAvataxCertified::AvataxLog.new('tax_svc', 'tax_service', 'call to tax service')
  end

  private

  def tax_calculation_enabled(prefs)
    ActiveRecord::Type::Boolean.new.cast(prefs["tax_calculation"])
  end

  def credential(prefs)
    'Basic ' + Base64.encode64(account_number(prefs) + ':' + license_key(prefs))
  end

  def service_url(prefs)
    prefs["endpoint"] + AVATAX_SERVICEPATH_TAX
  end

  def address_service_url(prefs)
    prefs["endpoint"] + AVATAX_SERVICEPATH_ADDRESS + 'validate?'
  end

  def license_key(prefs)
    prefs["license_key"]
  end

  def account_number(prefs)
    prefs["account"]
  end

  def response(uri, request_hash)
    prefs = Spree::AvalaraPreference.get_all_preferences

    res = RestClient::Request.execute(method: :post,
                                timeout: 5,
                                url: service_url(prefs) + uri,
                                payload:  JSON.generate(request_hash),
                                headers: {
                                  authorization: credential(prefs),
                                  content_type: 'application/json'
                                }
    )  do |response, request, result|
      response
    end

    JSON.parse(res)
  end

  def log(method, request_hash = nil)
    logger.info method.to_s + ' call'
    return if request_hash.nil?
    logger.debug request_hash
    logger.debug JSON.generate(request_hash)
  end
end
