class Object
  def boolean?; self == true || self == false; end
end

class Array
  def first=(_v); self[0]=_v; end
  def last=(_v); self[-1]=_v; end
end

class Integer
  def to_fileid(deg=4) # %04d
    return sprintf("%0#{deg}d", self)
  end
end

class Thread
  @@thread_pool = []
  alias init_exh initialize
  def initialize(*args, **kwargs, &block)
    @@thread_pool << self.object_id
    init_exh(*args, **kwargs, &block)
    ObjectSpace.define_finalizer(self, Thread.method(:_finalize))
  end

  def self._finalize(obj_id)
     @@thread_pool.delete(obj_id)
  end

  def self.kill_all
    @@thread_pool.each do |oid|
      kill(ObjectSpace._id2ref(oid)) rescue nil
    end
    @@thread_pool = []
  end
end

class Module
  def mattr_reader(*args)
    args.each do |var|
      define_singleton_method(var.to_sym){return class_eval("@#{var}");}
    end
  end

  def mattr_accessor(*args)
    mattr_reader(*args)
    args.each do |var|
      define_singleton_method((var.to_s + '=').to_sym){|v| return class_eval("@#{var} = #{v}");}
    end
  end
end