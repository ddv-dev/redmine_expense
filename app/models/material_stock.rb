class MaterialStock < ActiveRecord::Base
  # Генерируем хеш перед сохранением
  before_validation :generate_hash_key, on: :create
  before_validation :update_hash_key, on: :update
  
  validates :material_type, presence: true
  validates :brand, presence: true
  validates :model, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  
  # Уникальность хеш-ключа
  validates :hash_key, uniqueness: true, presence: true
  
  scope :available, -> { where('quantity > 0') }
  
  def self.find_by_attributes(attrs)
    hash_key = generate_hash_key_from_attrs(
      attrs[:material_type],
      attrs[:brand],
      attrs[:model]
    )
    find_by(hash_key: hash_key)
  end
  
  def self.find_or_create_by_attributes(attrs)
    hash_key = generate_hash_key_from_attrs(
      attrs[:material_type],
      attrs[:brand],
      attrs[:model]
    )
    
    find_or_create_by(hash_key: hash_key) do |record|
      record.material_type = attrs[:material_type]
      record.brand = attrs[:brand]
      record.model = attrs[:model]
      record.quantity = attrs[:quantity] || 0
    end
  end
  
  def display_name
    "#{material_type} | #{brand} | #{model}".strip
  end
  
  def sufficient_quantity?(needed)
    quantity >= needed
  end
  
  def deduct!(amount)
    update!(quantity: quantity - amount)
  end
  
  def add!(amount)
    update!(quantity: quantity + amount)
  end
  
  private
  
  def generate_hash_key
    self.hash_key = self.class.generate_hash_key_from_attrs(material_type, brand, model)
  end
  
  def update_hash_key
    if material_type_changed? || brand_changed? || model_changed?
      self.hash_key = self.class.generate_hash_key_from_attrs(material_type, brand, model)
    end
  end
  
  def self.generate_hash_key_from_attrs(material_type, brand, model)
    # Создаем строку для хеширования
    raw_string = "#{material_type.to_s.strip.downcase}|#{brand.to_s.strip.downcase}|#{model.to_s.strip.downcase}"
    
    # Генерируем MD5 хеш
    Digest::MD5.hexdigest(raw_string)
  end
end
