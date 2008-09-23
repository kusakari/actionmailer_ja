require 'jcode'
module ActionMailer
  module Ja
    # Subject, From, Recipients, Cc を自動的に base64 encode するかの真偽値。（デフォルト true）
    #
    # Examples:
    #  ActionMailer::Ja.auto_base64_encode = false
    #
    @@auto_base64_encode = true
    mattr_accessor :auto_base64_encode

    # 機種依存文字を安全な文字に置換するかの真偽値。（デフォルト false）
    #
    # Examples:
    #  ActionMailer::Ja.auto_replace_safe_char = true
    #
    @@auto_replace_safe_char = false
    mattr_accessor :auto_replace_safe_char

    # Mobile Mail Address
    attr_accessor :mobile

    def self.included(base) #:nodoc:
      base.class_eval do
        alias_method_chain :render_message, :jpmobile
        alias_method_chain :create!, :ja
        self.default_charset = 'iso-2022-jp' unless defined? Locale
      end
    end

    def base64_with_ja(text, charset="iso-2022-jp", convert=true)
      return nil if text.nil?
      if Array === text
        text.map! {|t| base64_with_ja(t)}
        return text
      end
      text = replace_safe_char(text) if auto_replace_safe_char
      if convert && charset == "iso-2022-jp"
        return NKF.nkf('-jW -M', text).strip
      else
        text = TMail::Base64.folding_encode(text)
        return "=?#{charset}?B?#{text}?="
      end
    end
    alias :base64 :base64_with_ja


    # Locale があるかどうかで GetText が読み込まれたかを判断する
    def gettext?
      return defined? Locale
    end

    def create_with_ja!(*arg) #:nodoc:
      create_without_ja!(*arg)
      part = @mail.parts.empty? ? @mail : @mail.parts.first
      if part.content_type == 'text/plain'
        if ((!gettext?) || (gettext? && Locale.get.language == "ja"))
          if self.mobile && self.mobile.softbank?
            part.charset = 'utf-8'
            part.body = NKF.nkf('-w', part.body)
          else
            part.charset = 'iso-2022-jp'
            part.body = NKF.nkf('-j', part.body)
          end
        end
      end
      @mail
    end

    # 携帯メールアドレスの場合、view テンプレートを変更します。
    # まず携帯キャリア別のテンプレートを探し存在すればそれを利用します。（拡張子は erb である必要はありません） 
    #
    #  xx_mobile_docomo.erb 
    #  xx_mobile_au.erb 
    #  xx_mobile_softbank.erb 
    #  xx_mobile_willcom.erb 
    #  xx_mobile_iphone.erb 
    #
    # 携帯キャリア別のテンプレートがない場合、携帯共通のテンプレートを探し存在すればそれを利用します。 
    #
    #  xx_mobile.erb 
    #
    # 携帯メール用テンプレートが存在しなければ、通常通りのテンプレートを利用します。 
    #
    #  xx.erb 
    #
    def render_message_with_jpmobile(method_name, body)
      if auto_base64_encode
        self.subject = base64_with_ja(self.subject)
        self.from = base64_with_ja(self.from)
        self.recipients = base64_with_ja(self.recipients)
        self.cc = base64_with_ja(self.cc)
      end
      if jp_mobile_addr = mobile_address
        self.mobile = jp_mobile_addr
        vals = []
        if Array === jp_mobile_addr.career_template_path
          jp_mobile_addr.career_template_path.each do |tp|
            vals << "mobile_#{tp}"
          end
        else
          vals << "mobile_#{jp_mobile_addr.career_template_path}"
        end
        vals << "mobile"
        vals.each do |v|
          mobile_path = "#{method_name}_#{v}"
          template_path = "#{template_root}/#{mailer_name}/#{mobile_path}"
          template_exists ||= Dir.glob("#{template_path}.*").any? { |i| File.basename(i).split(".").length > 0 }
          return render_message_without_jpmobile(mobile_path, body) if template_exists
        end
      end
      render_message_without_jpmobile(method_name, body)
    end

    # 機種依存文字を安全な文字に置換します。
    def replace_safe_char(src=nil)
      return nil if src.nil?
      return src.split(//).map {|c| (s = REPLACE_CHAR_MAP[c]).nil? ? c : s }.join
    end

    protected

    # 携帯メールアドレスオブジェクトを取得します。
    # 携帯メールアドレスでない場合、 nil が返されます。
    # recipients が複数指定されている場合、最初のメールアドレスで判断します。
    def mobile_address
      recipient = Array === recipients ? recipients[0] : recipients
      ActionMailer::JpMobile.constants.each do |const|
        c = ActionMailer::JpMobile.const_get(const)
        next if Hash === c
        if c::MAIL_ADDR_REGEXP =~ parse_mail_addr(recipient)
          return c.new
        end
      end
      nil
    end

    # recipient からメールアドレスを取り出します。
    def parse_mail_addr(recipient)
      /(.*?)<(.*?)>/ =~ recipient
      return $& ? $2 : recipient
    end
  end
end